package proxy

import (
	"context"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/accounts"
	"github.com/armanlife/firefox-vpn-client/core/internal/fxa"
	"github.com/armanlife/firefox-vpn-client/core/internal/guardian"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
)

const (
	proxyPassRenewLead  = 2 * time.Minute
	proxyPassRetryDelay = 30 * time.Second
	PassRenewTimeout    = 2 * time.Minute

	// quotaCheckInterval is how often the remaining monthly quota is polled
	// (HEAD, without minting a pass) so a token pool rotates as soon as a
	// token is exhausted, without waiting for the proxy pass to expire.
	quotaCheckInterval = 15 * time.Minute

	// proxyPassRenewAbandonGrace is how long a timed-out, cancelled renewal
	// may take to unwind before the process exits for a supervisor restart.
	proxyPassRenewAbandonGrace = 30 * time.Second

	// minRenewalInterval spaces successful renewals, so a pass that is
	// already due for renewal when it arrives cannot cause a tight loop.
	minRenewalInterval = 10 * time.Second

	// sessionRebuildCooldown limits how often tunnel failures may trigger a
	// Guardian round trip to rebuild the upstream session.
	sessionRebuildCooldown = 10 * time.Second

	// usageProbeBytes is the tunnel traffic after which the quota is read
	// before the next periodic check.
	usageProbeBytes = 512 << 20
)

var errRebuildCoolingDown = errors.New("upstream session rebuild is cooling down")

// recordRenewalOutcome stores the result of a renewal attempt for the status
// file. A nil err clears the failure fields.
func (c *Controller) recordRenewalOutcome(err error, retryAt time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err == nil {
		c.lastError = ""
		c.nextAttemptAt = time.Time{}
		c.lastRenewalAt = time.Now()
		return
	}
	c.lastError = renewalFailureCode(err)
	c.nextAttemptAt = retryAt
}

func (c *Controller) setUsage(usage *guardian.ProxyUsage) {
	if usage == nil {
		return
	}
	c.mu.Lock()
	c.usage = usage
	c.mu.Unlock()
}

// renewalFailureCode maps a renewal error to a stable status-file code.
func renewalFailureCode(err error) string {
	switch {
	case errors.Is(err, fxa.ErrReauthRequired):
		return "reauth_required"
	case errors.Is(err, guardian.ErrRegionUnavailable):
		return "region_unavailable"
	case errors.Is(err, accounts.ErrNoUsableAccount):
		return "no_usable_account"
	case errors.Is(err, guardian.ErrQuotaExceeded):
		return "quota_exhausted"
	case errors.Is(err, guardian.ErrNotEntitled):
		return "not_entitled"
	case errors.Is(err, guardian.ErrTokenInvalid):
		return "token_rejected"
	case errors.Is(err, context.DeadlineExceeded):
		return "timeout"
	case errors.Is(err, guardian.ErrServer):
		return "guardian_server_error"
	}
	return "renewal_failed"
}

// RenewalRetryDelay decides when a failed renewal is attempted again.
// Failures that retrying cannot fix soon back off for a long time instead
// of polling Guardian every proxyPassRetryDelay; a spent quota waits for its
// announced reset.
func RenewalRetryDelay(err error, now time.Time) time.Duration {
	var noAccount *accounts.NoUsableAccountError
	if errors.As(err, &noAccount) {
		if noAccount.RetryAt.IsZero() {
			return terminalRenewalRetryDelay
		}
		return min(max(noAccount.RetryAt.Sub(now)+time.Second, proxyPassRetryDelay), maxQuotaResetWait)
	}
	switch {
	case errors.Is(err, guardian.ErrQuotaExceeded):
		if usage := quotaUsageFromError(err); usage != nil && usage.Reset.After(now) {
			return min(usage.Reset.Sub(now)+time.Minute, maxQuotaResetWait)
		}
		if retryAfter := guardian.RetryAfter(err); retryAfter > 0 {
			return min(max(retryAfter, proxyPassRetryDelay), maxQuotaResetWait)
		}
		return terminalRenewalRetryDelay
	case errors.Is(err, fxa.ErrReauthRequired),
		errors.Is(err, guardian.ErrRegionUnavailable),
		errors.Is(err, guardian.ErrNotEntitled):
		return terminalRenewalRetryDelay
	}
	if retryAfter := guardian.RetryAfter(err); retryAfter > proxyPassRetryDelay {
		return min(retryAfter, terminalRenewalRetryDelay)
	}
	return proxyPassRetryDelay
}

func (c *Controller) RunRenewalLoop() {
	for {
		if c.isClosed() {
			return
		}
		expiry := c.currentExpiry()
		sleep := c.nextRenewalDelay()
		logx.Info("proxy pass renewal scheduled next_expiry=%s delay=%s", expiry.Format(time.RFC3339), sleep)
		if !c.sleepUntil(time.Now().Round(0).Add(sleep)) {
			return
		}
		logx.Info("proxy pass renewal starting")
		err, timedOut := c.renewWithTimeout(PassRenewTimeout)
		if timedOut {
			// The worker's context is cancelled; give it a bounded chance
			// to unwind before treating the process as wedged.
			if !c.waitRenewalUnwound(proxyPassRenewAbandonGrace) {
				logx.Error("proxy pass renewal did not stop within %s after timing out; exiting for supervisor restart", proxyPassRenewAbandonGrace)
				os.Exit(1)
			}
			err = fmt.Errorf("proxy pass renewal timed out after %s: %w", PassRenewTimeout, context.DeadlineExceeded)
		}
		if err == nil {
			continue
		}
		if c.isClosed() {
			return
		}
		now := time.Now()
		retry := RenewalRetryDelay(err, now)
		c.recordRenewalOutcome(err, now.Add(retry))
		logx.Warn("proxy pass renewal failed code=%s retry_in=%s err=%s", renewalFailureCode(err), retry, logx.Err(err))
		if hint := GuardianFailureHint(err); hint != "" {
			logx.Warn("%s", hint)
		}
		c.disableExpiredSession(now)
		c.writeStatus("renewal_failed")
		if !c.sleepOrDone(retry) {
			return
		}
	}
}

// renewWithTimeout runs one renewal whose context is cancelled after
// timeout. It reports timedOut when the deadline passed first; the worker
// then observes the cancellation and unwinds in the background.
func (c *Controller) renewWithTimeout(timeout time.Duration) (error, bool) {
	if timeout <= 0 {
		return c.renew(context.Background()), false
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	resultCh := make(chan error, 1)
	go func() {
		resultCh <- c.renew(ctx)
	}()

	timer := time.NewTimer(timeout)
	defer timer.Stop()

	select {
	case err := <-resultCh:
		cancel()
		return err, false
	case <-timer.C:
		cancel()
		return nil, true
	case <-c.done:
		cancel()
		return nil, false
	}
}

// waitRenewalUnwound waits until no renewal, rebuild, or quota transaction
// holds renewMu, or until grace elapses or the controller closes.
func (c *Controller) waitRenewalUnwound(grace time.Duration) bool {
	deadline := time.Now().Add(grace)
	for {
		if c.renewMu.TryLock() {
			c.renewMu.Unlock()
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
		if !c.sleepOrDone(100 * time.Millisecond) {
			return true
		}
	}
}

// wallCheckInterval bounds how long sleepUntil waits between looks at the
// wall clock.
const wallCheckInterval = 15 * time.Second

// sleepUntil waits until the wall clock reaches at (it must carry no
// monotonic reading) or the controller closes. A phone's suspended sleep
// does not advance Go's timers, but a pass expires by the wall clock: one
// long timer would fire after the pass expired, so the wait looks at the
// clock at least every wallCheckInterval and notices a wake-up quickly.
func (c *Controller) sleepUntil(at time.Time) bool {
	for {
		d := time.Until(at)
		if d <= 0 {
			return c.sleepOrDone(0)
		}
		if !c.sleepOrDone(min(d, wallCheckInterval)) {
			return false
		}
	}
}

func (c *Controller) sleepOrDone(d time.Duration) bool {
	if d <= 0 {
		select {
		case <-c.done:
			return false
		default:
			return true
		}
	}

	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-timer.C:
		return true
	case <-c.done:
		return false
	}
}

func (c *Controller) nextRenewalDelay() time.Duration {
	expiry := c.currentExpiry()
	if expiry.IsZero() {
		return proxyPassRetryDelay
	}
	renewAt := expiry.Add(-proxyPassRenewLead)
	delay := time.Until(renewAt)
	if delay < 0 {
		delay = 0
	}
	c.mu.Lock()
	lastRenewal := c.lastRenewalAt
	c.mu.Unlock()
	if !lastRenewal.IsZero() {
		if floor := minRenewalInterval - time.Since(lastRenewal); floor > delay {
			delay = floor
		}
	}
	return delay
}

func (c *Controller) renew(ctx context.Context) error {
	c.renewMu.Lock()
	defer c.renewMu.Unlock()
	if err := ctx.Err(); err != nil {
		return err
	}
	return c.renewLocked(ctx)
}

func (c *Controller) rebuildSession(failedSession *managedSession) error {
	c.renewMu.Lock()
	defer c.renewMu.Unlock()

	if c.hasUsableSessionOtherThan(failedSession, time.Now()) {
		logx.Debug("skipping proxy session rebuild: another usable session is already active")
		return nil
	}
	err := c.replaceSessionLocked()
	if err == nil && c.OnSessionRebuilt != nil {
		go c.OnSessionRebuilt()
	}
	return err
}

// replaceSessionLocked obtains a fresh pass and session for rebuildSession.
func (c *Controller) replaceSessionLocked() error {
	if c.refreshSession != nil {
		return c.refreshSession()
	}

	// Tunnel failures arrive per client request; without a cooldown a
	// persistent rejection (e.g. CONNECT 403 for a location the account
	// may not use) would turn every request into Guardian round trips.
	if !c.lastRebuildAt.IsZero() {
		if since := time.Since(c.lastRebuildAt); since < sessionRebuildCooldown {
			if c.lastRebuildErr != nil {
				return fmt.Errorf("%w (last attempt %s ago failed): %w", errRebuildCoolingDown, since.Round(time.Millisecond), c.lastRebuildErr)
			}
			return fmt.Errorf("%w: a session rebuilt with a fresh proxy pass failed again within %s (a persistent CONNECT 403 usually means the location requires an entitled account)", errRebuildCoolingDown, since.Round(time.Millisecond))
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), PassRenewTimeout)
	defer cancel()
	err := c.renewLocked(ctx)
	c.lastRebuildAt = time.Now()
	c.lastRebuildErr = err
	return err
}

func (c *Controller) renewLocked(ctx context.Context) error {
	_, pass, err := c.acquireUsablePass(ctx)
	if err != nil {
		return err
	}
	return c.adoptPass(pass)
}

// acquireUsablePass returns an auth and a proxy pass whose monthly quota is
// not yet exhausted. With an account pool, the pool picks the account and
// fails over between accounts. Without one (single fixed auth, as in tests),
// a Guardian rejection is recovered from by refreshing the OAuth token
// (HTTP 401) or activating the account (HTTP 403).
func (c *Controller) acquireUsablePass(ctx context.Context) (*runtimeAuth, *guardian.ProxyPassInfo, error) {
	if c.accounts != nil {
		auth, pass, err := c.accounts.AcquirePass(ctx, c.guardian)
		if err != nil {
			return nil, nil, err
		}
		c.mu.Lock()
		c.auth = auth
		c.mu.Unlock()
		c.setUsage(pass.Usage)
		return auth, pass, nil
	}
	auth, err := c.ensureOAuthToken(ctx)
	if err != nil {
		return nil, nil, err
	}
	setAuth := func(refreshed *runtimeAuth) {
		c.mu.Lock()
		c.auth = refreshed
		c.mu.Unlock()
	}
	pass, err := fetchProxyPassCtx(ctx, c.guardian, auth.Token.AccessToken)
	if errors.Is(err, guardian.ErrTokenInvalid) {
		auth, pass, err = recoverGuardianRejection(ctx, c.guardian, auth, err, setAuth)
	}
	if err != nil {
		c.setUsage(guardian.UsageFromError(err))
		return nil, nil, err
	}
	c.setUsage(pass.Usage)
	if isQuotaExhausted(pass) {
		return nil, nil, &passQuotaError{usage: pass.Usage}
	}
	return auth, pass, nil
}

// adoptPass applies pass to the current session: when the session supports
// in-place token updates the session is retained, otherwise a fresh session
// pool is built and swapped in while active tunnels drain gracefully.
func (c *Controller) adoptPass(pass *guardian.ProxyPassInfo) error {
	LogPassTimeCorrection(pass)
	c.setUsage(pass.Usage)

	if err := c.updateCurrentSessionToken(pass.RawToken, pass.ExpiresAt()); err == nil {
		c.recordRenewalOutcome(nil, time.Time{})
		c.writeStatus("token_updated")
		logx.Info("proxy pass renewed successfully next_expiry=%s session=retained", pass.ExpiresAt().Format(time.RFC3339))
		return nil
	} else {
		logx.Debug("existing upstream session cannot accept renewed proxy pass; rebuilding err=%s", logx.Err(err))
	}

	session, err := c.sessionFactory(pass.RawToken)
	if err != nil {
		return err
	}

	c.recordRenewalOutcome(nil, time.Time{})
	if !c.swapSession(session, pass.RawToken, pass.ExpiresAt()) {
		return ErrNoUsableSession
	}
	logx.Info("proxy pass renewed successfully next_expiry=%s", pass.ExpiresAt().Format(time.RFC3339))
	return nil
}

// RunQuotaMonitorLoop periodically checks the remaining monthly quota. With
// a session token pool it rotates to the next token once the quota is
// exhausted, without waiting for the proxy pass itself to expire.
func (c *Controller) RunQuotaMonitorLoop(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-c.done:
			return
		case <-ticker.C:
			c.checkQuota()
		case <-c.quotaCheckNow:
			logx.Debug("tunnel traffic reached the usage probe size; checking quota early")
			c.checkQuota()
		}
	}
}

// checkQuota reads the quota with a HEAD request, as Firefox does, so no
// pass is minted while quota remains. Only an exhausted quota with a token
// pool falls through to pass acquisition, which rotates the token.
func (c *Controller) checkQuota() {
	c.renewMu.Lock()
	defer c.renewMu.Unlock()

	c.trafficSinceCheck.Store(0)
	ctx, cancel := context.WithTimeout(context.Background(), PassRenewTimeout)
	defer cancel()

	auth, err := c.ensureOAuthToken(ctx)
	if err != nil {
		logx.Warn("quota check failed: %s", logx.Err(err))
		return
	}
	usageCtx, usageCancel := context.WithTimeout(ctx, APIRequestTimeout)
	usage, err := guardian.FetchProxyUsage(usageCtx, c.guardian, auth.Token.AccessToken)
	usageCancel()
	if errors.Is(err, guardian.ErrTokenInvalid) && !errors.Is(err, guardian.ErrNotEntitled) {
		// Guardian refused the access token: renew now, which refreshes
		// it and signs in again when Mozilla refuses the refresh token,
		// rather than at the next scheduled renewal.
		logx.Warn("Guardian refused the access token in the quota check; renewing now err=%s", logx.Err(err))
		if err := c.renewLocked(ctx); err != nil {
			now := time.Now()
			c.recordRenewalOutcome(err, now.Add(RenewalRetryDelay(err, now)))
			c.writeStatus("renewal_failed")
			logx.Warn("renewal after the quota check failed: %s", logx.Err(err))
		}
		return
	}
	if err != nil {
		logx.Warn("quota check failed: %s", logx.Err(err))
		return
	}
	c.setUsage(usage)
	handOver := usage.Exhausted()
	if c.accounts != nil && c.accounts.observeActiveUsage(usage) {
		handOver = true
		logx.Info("active account reached the switch threshold; switching account=%s", c.accounts.ActiveName())
	}
	c.writeStatus("quota_checked")
	if !handOver {
		return
	}
	if c.accounts == nil {
		logx.Warn("monthly proxy quota exhausted; new tunnels fail once the current proxy pass expires quota_reset=%s", usage.Reset.Format(time.RFC3339))
		return
	}

	_, pass, err := c.acquireUsablePass(ctx)
	if err != nil {
		logx.Warn("quota check failed: %s", logx.Err(err))
		return
	}

	c.mu.Lock()
	unchanged := c.current != nil && c.current.rawToken == pass.RawToken
	c.mu.Unlock()
	if unchanged {
		return
	}
	if err := c.adoptPass(pass); err != nil {
		logx.Warn("quota check: could not rebuild proxy sessions: %s", logx.Err(err))
		return
	}
	logx.Info("proxy sessions refreshed after token rotation")
}

func (c *Controller) ensureOAuthToken(ctx context.Context) (*runtimeAuth, error) {
	c.mu.Lock()
	auth := c.auth
	c.mu.Unlock()

	now := time.Now()
	if auth != nil && auth.accessTokenValid(now) {
		return auth, nil
	}
	if auth == nil || auth.Token == nil || auth.Token.RefreshToken == "" {
		return nil, fmt.Errorf("no refresh token available for background renewal")
	}

	logx.Info("refreshing OAuth token")
	refreshed, err := refreshRuntimeAuth(ctx, auth)
	if err != nil {
		return nil, err
	}

	c.mu.Lock()
	c.auth = refreshed
	c.mu.Unlock()
	logx.Info("OAuth token refreshed")
	return refreshed, nil
}

// SwitchAccountNow obtains a pass from the account the account pool now
// prefers (after a manual activation, removal, or disable) and applies it to
// the current upstream session without waiting for the next renewal.
func (c *Controller) SwitchAccountNow() error {
	c.renewMu.Lock()
	defer c.renewMu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), PassRenewTimeout)
	defer cancel()
	_, pass, err := c.acquireUsablePass(ctx)
	if err != nil {
		now := time.Now()
		c.recordRenewalOutcome(err, now.Add(RenewalRetryDelay(err, now)))
		c.writeStatus("renewal_failed")
		return err
	}
	return c.adoptPass(pass)
}
