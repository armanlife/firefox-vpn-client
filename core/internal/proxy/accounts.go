package proxy

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/accounts"
	"github.com/armanlife/firefox-vpn-client/core/internal/fxa"
	"github.com/armanlife/firefox-vpn-client/core/internal/guardian"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
)

// unavailableAccountRetry spaces retries of an account Guardian rejected
// even after refresh and activation.
const unavailableAccountRetry = 15 * time.Minute

// AccountPool connects the stored accounts to ProxyPass acquisition: it asks
// the manager for the account to use, loads and refreshes its credentials,
// and records every outcome (quota, rejection, sign-in requirement) so the
// manager can fail over to the next account.
type AccountPool struct {
	store *accounts.Store
	mgr   *accounts.Manager

	mu          sync.Mutex
	auths       map[string]*runtimeAuth
	lastRelogin map[string]time.Time
}

func NewAccountPool(store *accounts.Store, mgr *accounts.Manager) *AccountPool {
	return &AccountPool{store: store, mgr: mgr, auths: make(map[string]*runtimeAuth), lastRelogin: make(map[string]time.Time)}
}

// AuthFor returns the cached or stored credentials of an account.
func (p *AccountPool) AuthFor(acc accounts.Account) (*runtimeAuth, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if auth, ok := p.auths[acc.ID]; ok {
		return auth, nil
	}
	creds, err := p.store.Credentials(acc.ID)
	if err != nil {
		return nil, err
	}
	auth := &runtimeAuth{
		Token: &fxa.TokenResponse{
			AccessToken:  creds.AccessToken,
			RefreshToken: creds.RefreshToken,
			Scope:        creds.Scope,
			ExpiresIn:    creds.ExpiresIn,
			TokenType:    "bearer",
		},
		ObtainedAt: creds.ObtainedAt,
		accountID:  acc.ID,
		persist:    p.persist,
	}
	p.auths[acc.ID] = auth
	return auth, nil
}

// persist stores refreshed credentials in the account's own file and keeps
// them as the cached auth of that account.
func (p *AccountPool) persist(auth *runtimeAuth) error {
	p.mu.Lock()
	p.auths[auth.accountID] = auth
	p.mu.Unlock()
	return p.store.SaveCredentials(auth.accountID, &fxa.SavedTokens{
		AccessToken:  auth.Token.AccessToken,
		RefreshToken: auth.Token.RefreshToken,
		Scope:        auth.Token.Scope,
		ObtainedAt:   auth.ObtainedAt,
		ExpiresIn:    auth.Token.ExpiresIn,
	})
}

// ActiveName returns the display name of the active account.
func (p *AccountPool) ActiveName() string {
	if acc, ok := p.mgr.Active(); ok {
		return acc.Name()
	}
	return ""
}

// AcquirePass returns a usable ProxyPass from the active account or, when
// that account cannot supply one, from the next usable account in priority
// order. Failures that affect every account alike (network, Guardian
// outage, region refusal) are returned without trying other accounts.
func (p *AccountPool) AcquirePass(ctx context.Context, endpoint string) (*runtimeAuth, *guardian.ProxyPassInfo, error) {
	previous, hadActive := p.mgr.Active()
	tried := make(map[string]bool)
	for {
		acc, err := p.mgr.Candidate(tried)
		if err != nil {
			return nil, nil, err
		}
		tried[acc.ID] = true

		auth, pass, err := p.passFor(ctx, endpoint, acc)
		switch outcome := p.Record(acc, pass, err); outcome {
		case accountUsable:
			if err := p.mgr.Activate(acc.ID); err != nil {
				logx.Warn("persisting active account failed account=%s err=%s", acc.Name(), logx.Err(err))
			}
			if hadActive && previous.ID != acc.ID {
				logx.Info("active account switched from=%s to=%s reason=%q", previous.Name(), acc.Name(), accountStatusReason(p.mgr, previous.ID))
			} else if !hadActive {
				logx.Info("active account selected account=%s", acc.Name())
			}
			return auth, pass, nil
		case AccountSkipped:
			continue
		default:
			return nil, nil, err
		}
	}
}

// passFor refreshes the account's credentials when needed and fetches a
// pass, recovering from Guardian rejections like the single-account path.
// Whenever the tokens no longer work and cannot be renewed (the refresh
// token is revoked, or Guardian keeps refusing a refreshed access token),
// it signs in again with the stored password.
func (p *AccountPool) passFor(ctx context.Context, endpoint string, acc accounts.Account) (*runtimeAuth, *guardian.ProxyPassInfo, error) {
	auth, err := p.AuthFor(acc)
	if err != nil {
		err = fmt.Errorf("%w: loading credentials: %w", fxa.ErrReauthRequired, err)
	} else {
		auth, err = FreshRuntimeAuth(ctx, auth)
	}
	signedIn := false
	if errors.Is(err, fxa.ErrReauthRequired) {
		auth, err = p.Relogin(ctx, acc, err)
		signedIn = true
	}
	if err != nil {
		return nil, nil, err
	}
	pass, err := fetchProxyPassCtx(ctx, endpoint, auth.Token.AccessToken)
	if errors.Is(err, guardian.ErrTokenInvalid) {
		auth, pass, err = recoverGuardianRejection(ctx, endpoint, auth, err, nil)
		if !signedIn && tokensRefused(err) {
			if auth, err = p.Relogin(ctx, acc, err); err != nil {
				return nil, nil, err
			}
			pass, err = fetchProxyPassCtx(ctx, endpoint, auth.Token.AccessToken)
		}
	}
	return auth, pass, err
}

// tokensRefused reports whether err means the account's tokens are no
// longer accepted, which a new sign-in fixes. An account Guardian does not
// entitle stays refused with new tokens too.
func tokensRefused(err error) bool {
	if errors.Is(err, fxa.ErrReauthRequired) {
		return true
	}
	return errors.Is(err, guardian.ErrTokenInvalid) && !errors.Is(err, guardian.ErrNotEntitled)
}

type accountOutcome int

const (
	accountUsable accountOutcome = iota
	AccountSkipped
	accountFailed
)

// Record stores the quota state and status that the pass request revealed
// and classifies the outcome.
func (p *AccountPool) Record(acc accounts.Account, pass *guardian.ProxyPassInfo, err error) accountOutcome {
	var usage *guardian.ProxyUsage
	if pass != nil {
		usage = pass.Usage
	} else {
		usage = guardian.UsageFromError(err)
	}
	if usage != nil {
		reached, saveErr := p.mgr.ObserveUsage(acc.ID, AccountUsage(usage))
		if saveErr != nil {
			logx.Warn("saving account usage failed account=%s err=%s", acc.Name(), logx.Err(saveErr))
		}
		if reached {
			return AccountSkipped
		}
	}

	now := time.Now()
	var relogErr *ReloginError
	switch {
	case errors.As(err, &relogErr) && !relogErr.RetryAt.IsZero():
		logx.Warn("automatic sign-in postponed account=%s err=%s", acc.Name(), logx.Err(err))
		p.warnIfFailed(acc, p.mgr.MarkUnavailable(acc.ID, relogErr.why(), relogErr.RetryAt))
		p.Forget(acc.ID)
		return AccountSkipped
	case err == nil && isQuotaExhausted(pass):
		p.warnIfFailed(acc, p.mgr.Reserve(acc.ID, accounts.Why{Code: accounts.ReasonQuotaExhausted, Text: "monthly quota exhausted"}, resetTime(usage)))
		return AccountSkipped
	case err == nil:
		return accountUsable
	case errors.Is(err, guardian.ErrQuotaExceeded):
		reset := resetTime(usage)
		if reset.IsZero() {
			if retryAfter := guardian.RetryAfter(err); retryAfter > 0 {
				reset = now.Add(retryAfter)
			}
		}
		p.warnIfFailed(acc, p.mgr.Reserve(acc.ID, accounts.Why{Code: accounts.ReasonQuotaExhausted, Text: "monthly quota exhausted (HTTP 429)"}, reset))
		return AccountSkipped
	case errors.Is(err, fxa.ErrReauthRequired):
		logx.Warn("account needs a new sign-in account=%s err=%s", acc.Name(), logx.Err(err))
		why := accounts.Why{Code: accounts.ReasonSignInRequired, Text: "Firefox Account sign-in required"}
		if errors.As(err, &relogErr) {
			why = relogErr.why()
		}
		p.warnIfFailed(acc, p.mgr.MarkReauthRequired(acc.ID, why))
		p.Forget(acc.ID)
		return AccountSkipped
	case errors.Is(err, guardian.ErrTokenInvalid):
		logx.Warn("account rejected by Guardian account=%s err=%s", acc.Name(), logx.Err(err))
		p.warnIfFailed(acc, p.mgr.MarkUnavailable(acc.ID, accounts.Why{Code: accounts.ReasonNotEntitled, Text: "rejected by Guardian (not entitled or token refused)"}, now.Add(unavailableAccountRetry)))
		return AccountSkipped
	default:
		return accountFailed
	}
}

// observeActiveUsage records usage of the active account and reports
// whether it should hand over to the next account.
func (p *AccountPool) observeActiveUsage(usage *guardian.ProxyUsage) bool {
	acc, ok := p.mgr.Active()
	if !ok || usage == nil {
		return false
	}
	reached, err := p.mgr.ObserveUsage(acc.ID, AccountUsage(usage))
	if err != nil {
		logx.Warn("saving account usage failed account=%s err=%s", acc.Name(), logx.Err(err))
	}
	return reached
}

func (p *AccountPool) Forget(id string) {
	p.mu.Lock()
	delete(p.auths, id)
	p.mu.Unlock()
}

func (p *AccountPool) warnIfFailed(acc accounts.Account, err error) {
	if err != nil {
		logx.Warn("saving account status failed account=%s err=%s", acc.Name(), logx.Err(err))
	}
}

func AccountUsage(u *guardian.ProxyUsage) accounts.Usage {
	return accounts.Usage{
		Unlimited:      u.Unlimited,
		LimitBytes:     u.Limit,
		RemainingBytes: u.Remaining,
		ResetAt:        u.Reset,
		CheckedAt:      time.Now(),
	}
}

func resetTime(u *guardian.ProxyUsage) time.Time {
	if u == nil {
		return time.Time{}
	}
	return u.Reset
}

func accountStatusReason(mgr *accounts.Manager, id string) string {
	for _, acc := range mgr.Accounts() {
		if acc.ID == id {
			if acc.Reason != "" {
				return acc.Reason
			}
			return string(acc.Status)
		}
	}
	return ""
}

// DeviceRegistration enables the connected-services device record; tests
// turn it off so no background request outlives their mock transport.
var DeviceRegistration = func() *atomic.Bool { var b atomic.Bool; b.Store(true); return &b }()

// reloginRetry spaces automatic sign-ins of one account, so a password that
// Mozilla keeps asking to confirm does not trigger an email every minute.
// reloginNetworkRetry is the wait after a sign-in that did not reach
// Mozilla or met a temporary error.
const (
	reloginRetry        = 30 * time.Minute
	reloginNetworkRetry = 5 * time.Minute
)

// ReloginError explains why an automatic sign-in could not replace the
// account's tokens. Without RetryAt the user has to act (it reads as
// fxa.ErrReauthRequired); with RetryAt the account sits out until then and
// the sign-in is tried again.
type ReloginError struct {
	Reason  string
	RetryAt time.Time
	// Code and Detail say the same for the apps (accounts.Why).
	Code   string
	Detail string
	err    error
}

func (e *ReloginError) why() accounts.Why {
	return accounts.Why{Code: e.Code, Text: e.Reason, Detail: e.Detail}
}

func (e *ReloginError) Error() string { return e.Reason + ": " + e.err.Error() }
func (e *ReloginError) Unwrap() error { return e.err }

// Relogin signs in again with the account's stored password when its
// tokens stopped working and cannot be renewed. It works when Mozilla does
// not ask to confirm the sign-in; otherwise the account waits for "Sign in
// again" in the dashboard, which then only asks for the code. Without a
// stored password it returns cause.
func (p *AccountPool) Relogin(ctx context.Context, acc accounts.Account, cause error) (*runtimeAuth, error) {
	password, err := p.store.Password(acc.ID)
	if err != nil || acc.Email == "" {
		return nil, cause
	}
	p.mu.Lock()
	last := p.lastRelogin[acc.ID]
	recent := time.Since(last) < reloginRetry
	if !recent {
		p.lastRelogin[acc.ID] = time.Now()
	}
	p.mu.Unlock()
	if recent {
		next := last.Add(reloginRetry)
		return nil, &ReloginError{Reason: "The tokens stopped working soon after the last automatic sign-in; the next one is at " + next.Local().Format("15:04"), RetryAt: next, Code: accounts.ReasonSignInWait, err: cause}
	}

	logx.Info("the tokens stopped working; signing in again with the stored password account=%s", acc.Name())
	ctx, cancel := context.WithTimeout(ctx, 2*APIRequestTimeout)
	defer cancel()
	resp, err := fxa.Login(ctx, acc.Email, password)
	if err != nil {
		return nil, p.reloginFailed(acc, err)
	}
	// The session is not needed after the tokens (or when it waits for a
	// confirmation the user gives with "Sign in again", which signs in
	// anew); left alive it shows as "unknown" in connected services.
	defer func() {
		if err := fxa.DestroySession(ctx, resp.SessionToken); err != nil {
			logx.Warn("ending the sign-in session failed account=%s err=%s", acc.Name(), logx.Err(err))
		}
	}()
	if !resp.Verified {
		return nil, &ReloginError{Reason: "Mozilla asks to confirm the sign-in; use Sign in again (only the code is needed)", Code: accounts.ReasonSignInConfirm, err: fxa.ErrReauthRequired}
	}
	token, err := fxa.OAuthToken(ctx, resp.SessionToken)
	if err != nil {
		return nil, p.reloginFailed(acc, err)
	}
	auth := &runtimeAuth{Token: token, ObtainedAt: time.Now(), accountID: acc.ID, persist: p.persist}
	if err := auth.save(); err != nil {
		logx.Warn("saving the new tokens failed account=%s err=%s", acc.Name(), logx.Err(err))
	}
	logx.Info("signed in again automatically account=%s", acc.Name())
	go p.EnsureDevice(context.Background(), acc.ID)
	return auth, nil
}

// RecoverRevoked signs an account whose tokens Mozilla refused in again at
// once, before its access token expires. When that needs the user (no
// stored password, a confirmation code, a refused password), the account
// is marked for "Sign in again", except while it is the only account the
// proxy can use: its access token keeps working until it expires, and the
// renewal then marks it.
func (p *AccountPool) RecoverRevoked(ctx context.Context, acc accounts.Account, cause error) {
	_, err := p.Relogin(ctx, acc, cause)
	if err == nil {
		return
	}
	active, ok := p.mgr.Active()
	if ok && active.ID == acc.ID {
		if _, alt := p.mgr.Candidate(map[string]bool{acc.ID: true}); alt != nil {
			logx.Warn("the account must sign in again once its current access token expires account=%s err=%s", acc.Name(), logx.Err(err))
			return
		}
	}
	p.Record(acc, nil, err)
}

// reloginFailed classifies a failed automatic sign-in: Mozilla refusing
// the password or the sign-in needs the user; a network or temporary
// error is tried again after reloginNetworkRetry.
func (p *AccountPool) reloginFailed(acc accounts.Account, err error) error {
	if errors.Is(err, fxa.ErrReauthRequired) {
		return &ReloginError{Reason: "Automatic sign-in failed (" + fxa.Message(err) + "); sign in again", Code: accounts.ReasonSignInFailed, Detail: fxa.Message(err), err: err}
	}
	retryAt := time.Now().Add(reloginNetworkRetry)
	p.mu.Lock()
	delete(p.lastRelogin, acc.ID)
	p.mu.Unlock()
	return &ReloginError{Reason: "Automatic sign-in could not finish (" + fxa.Message(err) + "); trying again at " + retryAt.Local().Format("15:04"), RetryAt: retryAt, Code: accounts.ReasonSignInRetry, Detail: fxa.Message(err), err: err}
}

// EnsureDevice registers this program as "Firefox's built-in VPN" in the
// account's connected services, once per refresh token.
func (p *AccountPool) EnsureDevice(ctx context.Context, id string) {
	if !DeviceRegistration.Load() {
		return
	}
	acc, err := p.store.Get(id)
	if err != nil {
		return
	}
	creds, err := p.store.Credentials(id)
	if err != nil || creds.RefreshToken == "" {
		return
	}
	fingerprint := tokenFingerprint(creds.RefreshToken)
	if acc.DeviceID != "" && acc.DeviceToken == fingerprint {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, 2*APIRequestTimeout)
	defer cancel()
	device, err := fxa.RegisterDevice(ctx, creds.RefreshToken, "", fxa.DeviceName)
	if errors.Is(err, fxa.ErrReauthRequired) {
		// Mozilla refused the refresh token: it was revoked (for example
		// removed from the account's connected services). Guardian may
		// accept the access token for hours more, so nothing else would
		// notice before it expires.
		logx.Warn("Mozilla refused the account's refresh token; signing in again now account=%s err=%s", acc.Name(), fxa.Message(err))
		p.RecoverRevoked(ctx, acc, err)
		return
	}
	if err != nil {
		logx.Warn("registering the connected-services name failed account=%s err=%s", acc.Name(), fxa.Message(err))
		return
	}
	if err := p.store.SaveDevice(id, device.ID, fingerprint); err != nil {
		logx.Warn("saving the device record failed account=%s err=%s", acc.Name(), logx.Err(err))
		return
	}
	logx.Info("account shows as %q in its connected services account=%s", device.Name, acc.Name())
}

// EnsureDevices registers every account that has no device record yet.
func (p *AccountPool) EnsureDevices(ctx context.Context) {
	list, err := p.store.List()
	if err != nil {
		return
	}
	for _, acc := range list {
		if ctx.Err() != nil {
			return
		}
		p.EnsureDevice(ctx, acc.ID)
	}
}

func tokenFingerprint(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:6])
}
