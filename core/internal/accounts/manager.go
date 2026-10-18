package accounts

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/securefile"
)

const (
	// unknownResetRetry is how long an account whose quota reset time is
	// unknown (or already past) stays reserved before it is checked again.
	unknownResetRetry = time.Hour
)

// ErrNoUsableAccount signals that every enabled account is reserved,
// rejected, or waiting for a new sign-in.
var ErrNoUsableAccount = errors.New("no usable account")

// NoUsableAccountError reports why no account can be used and when the
// earliest one may become usable again.
type NoUsableAccountError struct {
	// RetryAt is the earliest time an account may be usable again; zero
	// when every account needs a new sign-in.
	RetryAt time.Time
	Summary string
}

func (e *NoUsableAccountError) Error() string {
	msg := "no usable account"
	if e.Summary != "" {
		msg += ": " + e.Summary
	}
	if !e.RetryAt.IsZero() {
		msg += fmt.Sprintf("; earliest retry %s", e.RetryAt.Format(time.RFC3339))
	}
	return msg
}

func (e *NoUsableAccountError) Unwrap() error { return ErrNoUsableAccount }

// Policy decides when an account has used enough of its quota.
type Policy struct {
	// ThresholdPercent is the used share of the limit at which the next
	// account takes over.
	ThresholdPercent float64
}

// ThresholdReached reports whether usage passed the switch threshold.
// Unlimited accounts and unknown usage never reach it.
func (p Policy) ThresholdReached(u *Usage) bool {
	if u == nil || u.Unlimited || u.LimitBytes <= 0 {
		return false
	}
	return float64(u.UsedBytes()) >= float64(u.LimitBytes)*p.ThresholdPercent/100
}

// Manager tracks the enabled accounts in priority order and the active
// account. The active account stays active until it becomes unusable, even
// when an account with a higher priority becomes usable again.
type Manager struct {
	mu        sync.Mutex
	store     *Store
	policy    Policy
	order     []string
	accounts  map[string]*Account
	active    string
	statePath string
	now       func() time.Time
}

type managerState struct {
	ActiveAccount string `json:"active_account"`
}

// NewManager loads the accounts named in order (highest priority first)
// and the persisted active account from statePath.
func NewManager(store *Store, order []string, policy Policy, statePath string) (*Manager, error) {
	m := &Manager{
		store:     store,
		policy:    policy,
		accounts:  make(map[string]*Account, len(order)),
		statePath: statePath,
		now:       time.Now,
	}
	for _, id := range order {
		acc, err := store.Get(id)
		if err != nil {
			return nil, fmt.Errorf("loading account %s: %w", id, err)
		}
		m.accounts[id] = &acc
		m.order = append(m.order, id)
	}
	if data, err := os.ReadFile(statePath); err == nil {
		var state managerState
		if json.Unmarshal(data, &state) == nil {
			if _, ok := m.accounts[state.ActiveAccount]; ok {
				m.active = state.ActiveAccount
			}
		}
	}
	return m, nil
}

// Policy returns the switching policy.
func (m *Manager) Policy() Policy {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.policy
}

// SetPolicy replaces the switching policy for future usage observations.
func (m *Manager) SetPolicy(policy Policy) {
	m.mu.Lock()
	m.policy = policy
	m.mu.Unlock()
}

// Reload replaces the enabled accounts with order (highest priority first),
// re-reading their records from the store. The active account stays active
// while it is still enabled; otherwise no account is active until the next
// Candidate/Activate.
func (m *Manager) Reload(order []string) error {
	loaded := make(map[string]*Account, len(order))
	for _, id := range order {
		acc, err := m.store.Get(id)
		if err != nil {
			return fmt.Errorf("loading account %s: %w", id, err)
		}
		loaded[id] = &acc
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.order = append([]string(nil), order...)
	m.accounts = loaded
	if _, ok := loaded[m.active]; !ok {
		m.active = ""
	}
	return nil
}

// Len returns the number of enabled accounts.
func (m *Manager) Len() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.order)
}

// Accounts returns a snapshot of the enabled accounts in priority order.
func (m *Manager) Accounts() []Account {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]Account, 0, len(m.order))
	for _, id := range m.order {
		out = append(out, *m.accounts[id])
	}
	return out
}

// Active returns the active account, if one was activated.
func (m *Manager) Active() (Account, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	acc, ok := m.accounts[m.active]
	if !ok {
		return Account{}, false
	}
	return *acc, true
}

// Candidate returns the account to try next, skipping ids in tried. The
// active account is preferred while it is usable; otherwise the first
// usable account in priority order is returned.
func (m *Manager) Candidate(tried map[string]bool) (Account, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := m.now()
	if acc, ok := m.accounts[m.active]; ok && !tried[m.active] && m.usableLocked(acc, now) {
		return *acc, nil
	}
	for _, id := range m.order {
		acc := m.accounts[id]
		if !tried[id] && m.usableLocked(acc, now) {
			return *acc, nil
		}
	}
	return Account{}, m.noUsableLocked()
}

// Activate makes id the active account and marks it ready.
func (m *Manager) Activate(id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	acc, ok := m.accounts[id]
	if !ok {
		return fmt.Errorf("unknown account %s", id)
	}
	if acc.Status != StatusReady || acc.Reason != "" || !acc.RetryAt.IsZero() {
		acc.Status, acc.Reason, acc.RetryAt = StatusReady, "", time.Time{}
		acc.ReasonCode, acc.ReasonDetail = "", ""
		if err := m.store.SaveState(*acc); err != nil {
			return err
		}
	}
	if m.active == id {
		return nil
	}
	m.active = id
	data, err := json.MarshalIndent(managerState{ActiveAccount: id}, "", "  ")
	if err != nil {
		return err
	}
	return securefile.WritePrivate(m.statePath, append(data, '\n'))
}

// ObserveUsage records the quota state of id. When the usage reached the
// switch threshold the account is reserved until its quota reset and
// reached is true.
func (m *Manager) ObserveUsage(id string, usage Usage) (reached bool, err error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	acc, ok := m.accounts[id]
	if !ok {
		return false, fmt.Errorf("unknown account %s", id)
	}
	if usage.CheckedAt.IsZero() {
		usage.CheckedAt = m.now()
	}
	acc.Usage = &usage
	reached = m.policy.ThresholdReached(&usage) || (!usage.Unlimited && usage.LimitBytes > 0 && usage.RemainingBytes <= 0)
	if reached {
		m.reserveLocked(acc, Why{Code: ReasonQuotaThreshold, Text: fmt.Sprintf("used %s of %s (switch threshold %g%%)", formatBytes(usage.UsedBytes()), formatBytes(usage.LimitBytes), m.policy.ThresholdPercent)}, usage.ResetAt)
	}
	return reached, m.store.SaveState(*acc)
}

// Reserve marks id as out of quota until resetAt (or a later re-check when
// the reset time is unknown).
func (m *Manager) Reserve(id string, why Why, resetAt time.Time) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	acc, ok := m.accounts[id]
	if !ok {
		return fmt.Errorf("unknown account %s", id)
	}
	m.reserveLocked(acc, why, resetAt)
	return m.store.SaveState(*acc)
}

// MarkReauthRequired takes id out of rotation until it is signed in again.
func (m *Manager) MarkReauthRequired(id string, why Why) error {
	return m.mark(id, StatusReauthRequired, why, time.Time{})
}

// MarkUnavailable takes id out of rotation until retryAt.
func (m *Manager) MarkUnavailable(id string, why Why, retryAt time.Time) error {
	return m.mark(id, StatusUnavailable, why, retryAt)
}

func (m *Manager) mark(id string, status Status, why Why, retryAt time.Time) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	acc, ok := m.accounts[id]
	if !ok {
		return fmt.Errorf("unknown account %s", id)
	}
	acc.Status, acc.Reason, acc.RetryAt = status, why.Text, retryAt
	acc.ReasonCode, acc.ReasonDetail = why.Code, why.Detail
	return m.store.SaveState(*acc)
}

func (m *Manager) reserveLocked(acc *Account, why Why, resetAt time.Time) {
	now := m.now()
	if resetAt.IsZero() || !resetAt.After(now) {
		resetAt = now.Add(unknownResetRetry)
	}
	acc.Status, acc.Reason, acc.RetryAt = StatusReserved, why.Text, resetAt
	acc.ReasonCode, acc.ReasonDetail = why.Code, why.Detail
}

// Why is the reason an account left the rotation: Text in the operator's
// English (the log, the dashboard), Code for the apps to put in their own
// words, Detail the error it carries, if any.
type Why struct{ Code, Text, Detail string }

// Reason codes (Account.ReasonCode).
const (
	// ReasonQuotaThreshold: the account reached the switch threshold.
	ReasonQuotaThreshold = "quota_threshold"
	// ReasonQuotaExhausted: Mozilla says the month's data is used up.
	ReasonQuotaExhausted = "quota_exhausted"
	// ReasonSignInRequired: the account must be signed in again.
	ReasonSignInRequired = "signin_required"
	// ReasonSignInConfirm: Mozilla wants the sign-in confirmed with a code.
	ReasonSignInConfirm = "signin_confirm"
	// ReasonSignInFailed: the automatic sign-in failed (Detail says why).
	ReasonSignInFailed = "signin_failed"
	// ReasonSignInWait: new tokens stopped working soon after the last
	// automatic sign-in; the next one is at RetryAt.
	ReasonSignInWait = "signin_wait"
	// ReasonSignInRetry: the automatic sign-in could not finish (Detail);
	// it is tried again at RetryAt.
	ReasonSignInRetry = "signin_retry"
	// ReasonNotEntitled: Guardian refused the account.
	ReasonNotEntitled = "not_entitled"
)

func (m *Manager) usableLocked(acc *Account, now time.Time) bool {
	switch acc.Status {
	case StatusReady:
		return true
	case StatusReserved, StatusUnavailable:
		return !acc.RetryAt.IsZero() && !now.Before(acc.RetryAt)
	default:
		return false
	}
}

func (m *Manager) noUsableLocked() *NoUsableAccountError {
	err := &NoUsableAccountError{}
	counts := map[Status]int{}
	for _, id := range m.order {
		acc := m.accounts[id]
		counts[acc.Status]++
		if (acc.Status == StatusReserved || acc.Status == StatusUnavailable) && !acc.RetryAt.IsZero() {
			if err.RetryAt.IsZero() || acc.RetryAt.Before(err.RetryAt) {
				err.RetryAt = acc.RetryAt
			}
		}
	}
	if len(m.order) == 0 {
		err.Summary = "no enabled accounts"
		return err
	}
	var parts []string
	for _, status := range []Status{StatusReserved, StatusUnavailable, StatusReauthRequired, StatusReady} {
		if counts[status] > 0 {
			parts = append(parts, fmt.Sprintf("%d %s", counts[status], status))
		}
	}
	err.Summary = strings.Join(parts, ", ")
	return err
}

func formatBytes(n int64) string {
	const gib = 1 << 30
	return fmt.Sprintf("%.1f GiB", float64(n)/gib)
}
