package service

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/controlplane"
)

type fixtureTransport struct{}

func (fixtureTransport) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, http.ErrNotSupported
}

// The relay setting installs its transport and takes away only that one:
// a transport set by someone else (a test's fixture) stays when no relay
// is configured.
func TestAPIRelayKeepsOtherTransports(t *testing.T) {
	t.Cleanup(func() { controlplane.SetTransport(nil); apiRelayTransport = nil })
	fixture := fixtureTransport{}
	controlplane.SetTransport(fixture)

	if err := configureAPIRelay(config.Network{}); err != nil {
		t.Fatal(err)
	}
	if controlplane.Transport() != (http.RoundTripper)(fixture) {
		t.Fatal("no relay must leave the fixture in place")
	}

	if err := configureAPIRelay(config.Network{APIRelay: "https://relay.example/?secret=k"}); err != nil {
		t.Fatal(err)
	}
	if controlplane.Transport() == (http.RoundTripper)(fixture) || controlplane.Transport() != apiRelayTransport {
		t.Fatal("the relay is installed")
	}
	if err := configureAPIRelay(config.Network{}); err != nil {
		t.Fatal(err)
	}
	if controlplane.Transport() == apiRelayTransport && apiRelayTransport != nil {
		t.Fatal("clearing the relay takes it away")
	}
	if apiRelayTransport != nil {
		t.Fatal("no relay is recorded")
	}
	if err := configureAPIRelay(config.Network{APIRelay: "http://relay.example/"}); err == nil {
		t.Fatal("a plain-http relay must be refused")
	}
}

// A request goes to the relay with the target in its url parameter, next
// to the relay's own key, with the method, headers, and body; the answer
// keeps the original request.
func TestRelayTransportForwardsToTarget(t *testing.T) {
	var got struct {
		target, key, method, header, body string
	}
	relay := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got.target, got.key = r.URL.Query().Get("url"), r.URL.Query().Get("secret")
		got.method, got.header = r.Method, r.Header.Get("Authorization")
		body, _ := io.ReadAll(r.Body)
		got.body = string(body)
		w.Header().Set("Set-Cookie", "challenge=1; Path=/")
		w.WriteHeader(http.StatusCreated)
		io.WriteString(w, "from the target")
	}))
	defer relay.Close()
	base, _ := url.Parse(relay.URL + "/relay.php?secret=s3")
	rt := &relayTransport{relay: base, base: relay.Client().Transport}

	req, _ := http.NewRequest(http.MethodPost, "https://vpn.mozilla.org/api/v1/fpn/token?a=1&b=2", strings.NewReader(`{"x":1}`))
	req.Header.Set("Authorization", "Bearer test")
	resp, err := rt.RoundTrip(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if got.target != "https://vpn.mozilla.org/api/v1/fpn/token?a=1&b=2" || got.key != "s3" {
		t.Fatalf("relay got target %q key %q", got.target, got.key)
	}
	if got.method != http.MethodPost || got.header != "Bearer test" || got.body != `{"x":1}` {
		t.Fatalf("relay got %+v", got)
	}
	if resp.StatusCode != http.StatusCreated || string(body) != "from the target" {
		t.Fatalf("answer %d %q", resp.StatusCode, body)
	}
	if resp.Request != req {
		t.Fatal("the answer must keep the original request, for cookies and redirects")
	}
}

// A relay that refuses (X-Relay-Error) is an error that names the relay.
func TestRelayTransportReportsRefusal(t *testing.T) {
	relay := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Relay-Error", "host not allowed")
		w.WriteHeader(http.StatusForbidden)
	}))
	defer relay.Close()
	base, _ := url.Parse(relay.URL)
	rt := &relayTransport{relay: base, base: relay.Client().Transport}
	req, _ := http.NewRequest(http.MethodGet, "https://example.com/", nil)
	_, err := rt.RoundTrip(req)
	if err == nil || !strings.Contains(err.Error(), "host not allowed") || !strings.Contains(err.Error(), base.Host) {
		t.Fatalf("got %v", err)
	}
}

func TestValidateRelay(t *testing.T) {
	for raw, ok := range map[string]bool{
		"":                                       true,
		"https://relay.example.workers.dev":      true,
		"https://example.com/relay.php?secret=k": true,
		"http://example.com/relay.php":           false,
		"relay.example":                          false,
	} {
		if err := config.ValidateRelay(raw); (err == nil) != ok {
			t.Errorf("%q: %v", raw, err)
		}
	}
}

// counting passes requests on and counts them.
type counting struct {
	n  atomic.Int32
	rt http.RoundTripper
}

func (c *counting) RoundTrip(r *http.Request) (*http.Response, error) {
	c.n.Add(1)
	return c.rt.RoundTrip(r)
}

// newFallback is a relayFallback whose relay answers "relayed" with the
// body it got, and counts its requests.
func newFallback(t *testing.T) (*relayFallback, *counting, *atomic.Int32) {
	t.Helper()
	var hits atomic.Int32
	relay := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		body, _ := io.ReadAll(r.Body)
		io.WriteString(w, "relayed "+r.URL.Query().Get("url")+" "+string(body))
	}))
	t.Cleanup(relay.Close)
	base, _ := url.Parse(relay.URL + "/?secret=k")
	direct := &counting{rt: &http.Transport{}}
	return &relayFallback{direct: direct, relay: &relayTransport{relay: base, base: relay.Client().Transport}}, direct, &hits
}

func send(t *testing.T, rt http.RoundTripper, method, target, body string) string {
	t.Helper()
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req, _ := http.NewRequest(method, target, r)
	resp, err := rt.RoundTrip(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	got, _ := io.ReadAll(resp.Body)
	return string(got)
}

// Mozilla answering directly: the relay is not used.
func TestRelayFallbackGoesDirectFirst(t *testing.T) {
	mozilla := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		io.WriteString(w, "direct")
	}))
	defer mozilla.Close()
	fb, _, relayed := newFallback(t)
	if got := send(t, fb, http.MethodGet, mozilla.URL, ""); got != "direct" || relayed.Load() != 0 {
		t.Fatalf("got %q, relay used %d times", got, relayed.Load())
	}
}

// Mozilla unreachable: the request, body and all, goes through the relay,
// and the next ones go there first, without waiting for Mozilla again.
func TestRelayFallbackUsesTheRelayWhenMozillaIsUnreachable(t *testing.T) {
	closed := "http://127.0.0.1:1/token"
	fb, direct, relayed := newFallback(t)
	if got := send(t, fb, http.MethodPost, closed, "payload"); got != "relayed "+closed+" payload" {
		t.Fatalf("got %q", got)
	}
	send(t, fb, http.MethodGet, closed, "")
	if direct.n.Load() != 1 || relayed.Load() != 2 {
		t.Fatalf("direct %d, relayed %d", direct.n.Load(), relayed.Load())
	}
	// After a while, directly again.
	fb.relayUntil = time.Now().Add(-time.Second)
	send(t, fb, http.MethodGet, closed, "")
	if direct.n.Load() != 2 {
		t.Fatalf("direct %d", direct.n.Load())
	}
}

// Mozilla refusing the region (HTTP 451) also goes through the relay.
func TestRelayFallbackUsesTheRelayForTheRegion(t *testing.T) {
	mozilla := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusUnavailableForLegalReasons)
	}))
	defer mozilla.Close()
	fb, _, relayed := newFallback(t)
	if got := send(t, fb, http.MethodGet, mozilla.URL+"/token", ""); got != "relayed "+mozilla.URL+"/token " || relayed.Load() != 1 {
		t.Fatalf("got %q, relayed %d", got, relayed.Load())
	}
}

// A request that reached Mozilla and then failed is not sent again
// through the relay: it may have been done.
func TestRelayFallbackDoesNotSendTwice(t *testing.T) {
	mozilla := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		conn, _, _ := w.(http.Hijacker).Hijack()
		conn.Close()
	}))
	defer mozilla.Close()
	fb, _, relayed := newFallback(t)
	req, _ := http.NewRequest(http.MethodPost, mozilla.URL, strings.NewReader("code"))
	if _, err := fb.RoundTrip(req); err == nil {
		t.Fatal("the cut request succeeded")
	}
	if relayed.Load() != 0 {
		t.Fatalf("relayed %d", relayed.Load())
	}
}
