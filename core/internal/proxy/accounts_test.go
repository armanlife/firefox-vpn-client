package proxy

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/accounts"
	"github.com/armanlife/firefox-vpn-client/core/internal/fxa"
	"github.com/armanlife/firefox-vpn-client/core/internal/guardian"
)

// All credentials in this file are local fixtures; the control plane
// transport rejects every request it does not recognise.

const testGiB = int64(1) << 30

var quotaReset = time.Now().Add(72 * time.Hour).UTC().Truncate(time.Second)

func accountJWT(sub string) string {
	now := time.Now()
	claims := fmt.Sprintf(`{"sub":%q,"aud":"https://vpn.mozilla.org","iss":"https://vpn.mozilla.org","iat":%d,"nbf":%d,"exp":%d}`, sub, now.Unix(), now.Unix(), now.Add(10*time.Minute).Unix())
	return "e30." + base64.RawURLEncoding.EncodeToString([]byte(claims)) + ".local-only"
}

func quotaHeader(usedGiB int64) http.Header {
	h := make(http.Header)
	h.Set("X-Quota-Limit", strconv.FormatInt(50*testGiB, 10))
	h.Set("X-Quota-Remaining", strconv.FormatInt((50-usedGiB)*testGiB, 10))
	h.Set("X-Quota-Reset", quotaReset.Format(time.RFC3339))
	return h
}

// newTestAccountPool stores one account per name with a valid access token
// "access-<name>" and refresh token "refresh-<name>".
func newTestAccountPool(t *testing.T, names ...string) (*AccountPool, map[string]accounts.Account) {
	t.Helper()
	dir := t.TempDir()
	store, err := accounts.OpenStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	byName := make(map[string]accounts.Account)
	var order []string
	for i, name := range names {
		acc, _, err := store.Add(name+"@example.com", &fxa.SavedTokens{
			AccessToken: "access-" + name, RefreshToken: "refresh-" + name, ObtainedAt: time.Now(), ExpiresIn: 3600,
		}, time.Now().Add(time.Duration(i)*time.Second))
		if err != nil {
			t.Fatal(err)
		}
		byName[name] = acc
		order = append(order, acc.ID)
	}
	mgr, err := accounts.NewManager(store, order, accounts.Policy{ThresholdPercent: 90}, filepath.Join(dir, "state.json"))
	if err != nil {
		t.Fatal(err)
	}
	return NewAccountPool(store, mgr), byName
}

func accountFromBearer(r *http.Request) string {
	return strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer access-")
}

func accountStatus(t *testing.T, pool *AccountPool, id string) accounts.Account {
	t.Helper()
	for _, acc := range pool.mgr.Accounts() {
		if acc.ID == id {
			return acc
		}
	}
	t.Fatalf("account %s not found", id)
	return accounts.Account{}
}

func TestAccountPoolSwitchesAtUsageThreshold(t *testing.T) {
	pool, accs := newTestAccountPool(t, "a", "b")
	setCoreControlPlane(t, func(r *http.Request) (*http.Response, error) {
		switch accountFromBearer(r) {
		case "a":
			return coreResponse(r, http.StatusOK, `{"token":"`+accountJWT("a")+`"}`, quotaHeader(46)), nil
		case "b":
			return coreResponse(r, http.StatusOK, `{"token":"`+accountJWT("b")+`"}`, quotaHeader(3)), nil
		}
		return nil, fmt.Errorf("unexpected request %s", r.URL)
	})

	auth, pass, err := pool.AcquirePass(context.Background(), "https://guardian.invalid")
	if err != nil {
		t.Fatal(err)
	}
	if auth.accountID != accs["b"].ID || !strings.Contains(pass.Claims.Sub, "b") {
		t.Fatalf("expected account b to supply the pass, got account %s sub %s", auth.accountID, pass.Claims.Sub)
	}
	if active, _ := pool.mgr.Active(); active.ID != accs["b"].ID {
		t.Fatalf("expected b to be active, got %+v", active)
	}
	if a := accountStatus(t, pool, accs["a"].ID); a.Status != accounts.StatusReserved || !a.RetryAt.Equal(quotaReset) {
		t.Fatalf("expected a to be reserved until the quota reset, got %+v", a)
	}
}

func TestAccountPoolSkipsExhaustedAndSignedOutAccounts(t *testing.T) {
	pool, accs := newTestAccountPool(t, "a", "b", "c")
	// b's access token has expired and its refresh token was revoked.
	if err := pool.store.SaveCredentials(accs["b"].ID, &fxa.SavedTokens{AccessToken: "access-b", RefreshToken: "refresh-b", ObtainedAt: time.Now().Add(-48 * time.Hour), ExpiresIn: 3600}); err != nil {
		t.Fatal(err)
	}
	setCoreControlPlane(t, func(r *http.Request) (*http.Response, error) {
		if r.URL.Host == "api.accounts.firefox.com" {
			return coreResponse(r, http.StatusBadRequest, `{"code":400,"errno":110,"message":"Invalid token"}`, nil), nil
		}
		switch accountFromBearer(r) {
		case "a":
			h := quotaHeader(50)
			h.Set("Retry-After", "3600")
			return coreResponse(r, http.StatusTooManyRequests, "quota", h), nil
		case "c":
			return coreResponse(r, http.StatusOK, `{"token":"`+accountJWT("c")+`"}`, quotaHeader(1)), nil
		}
		return nil, fmt.Errorf("unexpected request %s", r.URL)
	})

	auth, _, err := pool.AcquirePass(context.Background(), "https://guardian.invalid")
	if err != nil || auth.accountID != accs["c"].ID {
		t.Fatalf("expected account c, got %+v %v", auth, err)
	}
	if a := accountStatus(t, pool, accs["a"].ID); a.Status != accounts.StatusReserved {
		t.Fatalf("expected a reserved, got %+v", a)
	}
	if b := accountStatus(t, pool, accs["b"].ID); b.Status != accounts.StatusReauthRequired {
		t.Fatalf("expected b to need a sign-in, got %+v", b)
	}
}

func TestAccountPoolDoesNotSwitchOnSharedFailure(t *testing.T) {
	pool, accs := newTestAccountPool(t, "a", "b")
	var requestsForB atomic.Int32
	setCoreControlPlane(t, func(r *http.Request) (*http.Response, error) {
		if accountFromBearer(r) == "b" {
			requestsForB.Add(1)
		}
		return coreResponse(r, http.StatusUnavailableForLegalReasons, "region", nil), nil
	})

	_, _, err := pool.AcquirePass(context.Background(), "https://guardian.invalid")
	if !errors.Is(err, guardian.ErrRegionUnavailable) || requestsForB.Load() != 0 {
		t.Fatalf("expected a region error without trying b, got %v (b requests %d)", err, requestsForB.Load())
	}
	if a := accountStatus(t, pool, accs["a"].ID); a.Status != accounts.StatusReady {
		t.Fatalf("a shared failure must not change the account status, got %+v", a)
	}
}

func TestAccountPoolReportsWhenEveryAccountIsReserved(t *testing.T) {
	pool, _ := newTestAccountPool(t, "a", "b")
	setCoreControlPlane(t, func(r *http.Request) (*http.Response, error) {
		return coreResponse(r, http.StatusOK, `{"token":"`+accountJWT(accountFromBearer(r))+`"}`, quotaHeader(47)), nil
	})

	_, _, err := pool.AcquirePass(context.Background(), "https://guardian.invalid")
	var noAccount *accounts.NoUsableAccountError
	if !errors.As(err, &noAccount) || !noAccount.RetryAt.Equal(quotaReset) {
		t.Fatalf("expected no usable account until the reset, got %v", err)
	}
	if renewalFailureCode(err) != "no_usable_account" {
		t.Fatalf("unexpected failure code %q", renewalFailureCode(err))
	}
	// The reset is three days away, so the wait is capped.
	if delay := RenewalRetryDelay(err, time.Now()); delay != maxQuotaResetWait {
		t.Fatalf("expected the wait to be capped at %s, got %s", maxQuotaResetWait, delay)
	}
}

func TestControllerQuotaCheckSwitchesAccountWithoutNewSession(t *testing.T) {
	pool, accs := newTestAccountPool(t, "a", "b")
	if err := pool.mgr.Activate(accs["a"].ID); err != nil {
		t.Fatal(err)
	}
	authA, err := pool.AuthFor(accs["a"])
	if err != nil {
		t.Fatal(err)
	}
	passB := accountJWT("b")
	setCoreControlPlane(t, func(r *http.Request) (*http.Response, error) {
		switch {
		case r.Method == http.MethodHead && accountFromBearer(r) == "a":
			return coreResponse(r, http.StatusOK, "", quotaHeader(46)), nil
		case r.Method == http.MethodGet && accountFromBearer(r) == "a":
			return coreResponse(r, http.StatusOK, `{"token":"`+accountJWT("a")+`"}`, quotaHeader(46)), nil
		case r.Method == http.MethodGet && accountFromBearer(r) == "b":
			return coreResponse(r, http.StatusOK, `{"token":"`+passB+`"}`, quotaHeader(2)), nil
		}
		return nil, fmt.Errorf("unexpected request %s %s", r.Method, r.URL)
	})

	session := &fakeProxySession{token: "pass-a"}
	controller := &Controller{
		guardian:      "https://guardian.invalid",
		accounts:      pool,
		auth:          authA,
		quotaCheckNow: make(chan struct{}, 1),
		done:          make(chan struct{}),
		current:       &managedSession{session: session, rawToken: "pass-a", expiresAt: time.Now().Add(10 * time.Minute), accepting: true},
		sessionFactory: func(string) (proxySession, error) {
			return nil, errors.New("an account switch must not rebuild the upstream session")
		},
	}

	controller.checkQuota()

	if got := session.currentToken(); got != passB {
		t.Fatal("expected the existing upstream session to carry account b's pass")
	}
	if active, _ := pool.mgr.Active(); active.ID != accs["b"].ID {
		t.Fatalf("expected b to be active, got %+v", active)
	}
	if status := controller.CurrentStatus("quota_checked"); status.ActiveAccount != "b@example.com" {
		t.Fatalf("expected the status to name account b, got %q", status.ActiveAccount)
	}
}

func TestNoteTrafficRequestsEarlyQuotaCheck(t *testing.T) {
	t.Parallel()

	controller := &Controller{quotaCheckNow: make(chan struct{}, 1)}
	controller.noteTraffic(usageProbeBytes - 1)
	select {
	case <-controller.quotaCheckNow:
		t.Fatal("no check expected below the probe size")
	default:
	}
	controller.noteTraffic(1)
	select {
	case <-controller.quotaCheckNow:
	default:
		t.Fatal("expected an early quota check request")
	}
	if controller.trafficSinceCheck.Load() != 0 {
		t.Fatal("expected the traffic counter to reset")
	}
}
