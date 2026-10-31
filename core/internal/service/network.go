package service

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"net/http/httptrace"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/controlplane"
	"github.com/armanlife/firefox-vpn-client/core/internal/hellosplit"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/resolver"
)

const apiRelayDialTimeout = 20 * time.Second

// resolverDialer dials through the configured DNS servers with a timeout.
type resolverDialer struct{ timeout time.Duration }

func (d resolverDialer) DialContext(ctx context.Context, network, address string) (net.Conn, error) {
	ctx, cancel := context.WithTimeout(ctx, d.timeout)
	defer cancel()
	conn, err := resolver.Dial(ctx, network, address)
	if err != nil {
		return nil, err
	}
	return hellosplit.Wrap(conn), nil
}

func (d resolverDialer) Dial(network, address string) (net.Conn, error) {
	return d.DialContext(context.Background(), network, address)
}

// configureDNS installs the configured DNS servers for every connection
// this program opens itself.
func configureDNS(cfg config.DNS) error {
	r, err := resolver.New(cfg.Servers, cfg.FallbackToSystem)
	if err != nil {
		return err
	}
	if r.System() {
		resolver.Set(nil)
		logx.Info("DNS: system resolver")
		return nil
	}
	resolver.Set(r)
	logx.Info("DNS: servers=%s", r)
	return nil
}

// configureAPIRelay sends the control-plane requests through the user's
// relay at n.APIRelay when they cannot go directly (relayFallback); empty
// sends them directly only. Only the Firefox Accounts, Guardian,
// server-list, geo-file, and flag requests are affected; the VPN traffic
// keeps talking to Mozilla's proxy directly. n.APIRelayECH hides the
// relay's name with Encrypted Client Hello (echDialer).
func configureAPIRelay(n config.Network) error {
	hellosplit.Set(n.HelloSplit)
	proxyAddress := n.UpstreamProxyInUse()
	if err := resolver.SetUpstreamProxy(proxyAddress, n.UpstreamProxyUsername, n.UpstreamProxyPassword); err != nil {
		return err
	}
	if proxyAddress != "" {
		logx.Info("connections to Mozilla and the control plane go through the upstream proxy=%s", proxyAddress)
	}
	raw := strings.TrimSpace(n.APIRelay)
	if raw == "" {
		// Only a relay this function set is taken away: another transport
		// (a test's fixture) stays, so starting a daemon never sends a
		// test's requests to the real services.
		if apiRelayTransport != nil && controlplane.Transport() == apiRelayTransport {
			controlplane.SetTransport(nil)
		}
		apiRelayTransport = nil
		return nil
	}
	if err := config.ValidateRelay(raw); err != nil {
		return err
	}
	relay, _ := url.Parse(raw)
	dialer := resolverDialer{timeout: apiRelayDialTimeout}
	base := &http.Transport{
		DialContext:     dialer.DialContext,
		TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12},
	}
	ech := "off"
	if n.APIRelayECH != config.RelayECHOff {
		d, err := newECHDialer(relay.Hostname(), n, dialer.DialContext)
		if err != nil {
			return err
		}
		base.DialTLSContext = d.DialTLSContext
		ech = config.RelayECHOn
		if d.require {
			ech = config.RelayECHRequire
		}
	}
	transport := &relayFallback{
		direct: controlplane.QuickTransport(directWait),
		relay:  &relayTransport{relay: relay, base: base},
	}
	controlplane.SetTransport(transport)
	apiRelayTransport = transport
	logx.Info("control plane API requests sent directly, and through relay=%s ech=%s when that fails", relay.Host, ech)
	return nil
}

const (
	// directWait is how long a request tries to reach Mozilla directly
	// (the connection and TLS each, once the name is known) before it goes
	// through the relay.
	directWait = 4 * time.Second
	// relayFirstFor is how long, after a request had to go through the
	// relay, the next ones go there first, without trying directly.
	relayFirstFor = 10 * time.Minute
)

// relayFallback sends each control-plane request directly, and through the
// user's relay when that cannot work: no connection to the server within
// directWait (nothing was sent, so nothing is sent twice), or Mozilla
// refusing the region (HTTP 451). After such a request the next ones go
// through the relay first for relayFirstFor, or until the network changes,
// so only the first waits; then directly again. A relay that cannot be
// reached falls back to the direct way the same way. So a relay set by
// mistake costs nothing where Mozilla answers.
type relayFallback struct {
	direct http.RoundTripper
	relay  *relayTransport

	mu         sync.Mutex
	relayUntil time.Time
	network    string
}

func (t *relayFallback) RoundTrip(req *http.Request) (*http.Response, error) {
	first, second := http.RoundTripper(t.direct), http.RoundTripper(t.relay)
	if t.relayFirst() {
		first, second = second, first
	}
	resp, why, err := t.try(first, req)
	if why == "" {
		return resp, err
	}
	if first == t.direct {
		t.useRelay(why)
	}
	retry, _, retryErr := t.try(second, req)
	if first == t.relay && retryErr == nil {
		// The relay failed, Mozilla answered: directly from now on.
		t.mu.Lock()
		t.relayUntil = time.Time{}
		t.mu.Unlock()
	}
	if retryErr != nil && err != nil {
		return nil, fmt.Errorf("%w; %s: %w", err, t.relay.relay.Host, retryErr)
	}
	return retry, retryErr
}

// try sends req through rt. why is set when another way may be tried: the
// server could not be reached (no connection: nothing was sent), or the
// answer is HTTP 451 (closed).
func (t *relayFallback) try(rt http.RoundTripper, req *http.Request) (*http.Response, string, error) {
	out := req.Clone(req.Context())
	if req.Body != nil && req.GetBody != nil {
		body, err := req.GetBody()
		if err != nil {
			return nil, "", err
		}
		out.Body = body
	}
	var connected atomic.Bool
	out = out.WithContext(httptrace.WithClientTrace(out.Context(), &httptrace.ClientTrace{
		GotConn: func(httptrace.GotConnInfo) { connected.Store(true) },
	}))
	resp, err := rt.RoundTrip(out)
	retryable := req.Body == nil || req.GetBody != nil
	switch {
	case err != nil && !connected.Load() && req.Context().Err() == nil && retryable:
		return nil, logx.Err(err), err
	case err == nil && resp.StatusCode == http.StatusUnavailableForLegalReasons && retryable:
		resp.Body.Close()
		return nil, "HTTP 451", fmt.Errorf("%s: HTTP 451", req.URL.Host)
	}
	if resp != nil {
		resp.Request = req
	}
	return resp, "", err
}

// relayFirst reports whether requests go through the relay first now.
func (t *relayFallback) relayFirst() bool {
	network, _ := networkNow()
	t.mu.Lock()
	defer t.mu.Unlock()
	if network != t.network || time.Now().After(t.relayUntil) {
		if !t.relayUntil.IsZero() {
			logx.Info("control plane: trying Mozilla directly again")
		}
		t.relayUntil = time.Time{}
		return false
	}
	return true
}

func (t *relayFallback) useRelay(why string) {
	network, _ := networkNow()
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.relayUntil.IsZero() {
		logx.Warn("control plane: Mozilla not reached directly, through relay=%s for %s err=%s", t.relay.relay.Host, relayFirstFor, why)
	}
	t.relayUntil, t.network = time.Now().Add(relayFirstFor), network
}

// apiRelayTransport is the transport configureAPIRelay installed; nil when
// no relay is set.
var apiRelayTransport http.RoundTripper

// relayTransport sends each request to the relay, with the target URL in
// the relay's url parameter (next to its own parameters, such as its secret),
// and the method, headers, and body as they are; the relay forwards it and
// answers with the target's response. The response keeps the original
// request, so cookies and redirects resolve against the target. A relay
// that refuses (scripts/relay set X-Relay-Error) is an error that names
// the relay.
type relayTransport struct {
	relay *url.URL
	base  http.RoundTripper
}

func (t *relayTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	target := *t.relay
	query := target.Query()
	query.Set("url", req.URL.String())
	target.RawQuery = query.Encode()
	out := req.Clone(req.Context())
	out.URL = &target
	out.Host = ""
	resp, err := t.base.RoundTrip(out)
	if err != nil {
		return nil, fmt.Errorf("API relay %s: %w", t.relay.Host, err)
	}
	if reason := resp.Header.Get("X-Relay-Error"); reason != "" {
		resp.Body.Close()
		return nil, fmt.Errorf("API relay %s refused %s: %s", t.relay.Host, req.URL.Host, reason)
	}
	resp.Request = req
	return resp, nil
}
