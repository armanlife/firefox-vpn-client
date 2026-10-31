package service

import (
	"context"
	"testing"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/netcheck"
	"github.com/armanlife/firefox-vpn-client/core/internal/proxy"
	"github.com/armanlife/firefox-vpn-client/core/internal/resolver"
)

// A failure that may be the device's own is checked against the internet:
// without it, it is no_network; with it, a name or route that fails is
// Mozilla's servers filtered. The account's problems need no check.
func TestCheckedFailure(t *testing.T) {
	old, oldInside := netcheck.Check, netcheck.InsideVPN
	t.Cleanup(func() { netcheck.Check, netcheck.InsideVPN = old, oldInside })
	cases := []struct {
		code  string
		check netcheck.Result
		want  string
	}{
		{proxy.FailureUnreachable, netcheck.Offline, proxy.FailureNoNetwork},
		{proxy.FailureOther, netcheck.Offline, proxy.FailureNoNetwork},
		{proxy.FailureNoNetwork, netcheck.Online, proxy.FailureUnreachable},
		{proxy.FailureUnreachable, netcheck.Online, proxy.FailureUnreachable},
		{proxy.FailureOther, netcheck.Online, proxy.FailureOther},
		{proxy.FailureNoNetwork, netcheck.Unknown, proxy.FailureNoNetwork},
		{proxy.FailureQuota, netcheck.Offline, proxy.FailureQuota},
	}
	for _, tc := range cases {
		calls := 0
		netcheck.Check = func(context.Context) netcheck.Result { calls++; return tc.check }
		insideVPNSeen.at = time.Time{}
		if got := checkedFailure(tc.code); got != tc.want {
			t.Errorf("%s with %v: %q, want %q", tc.code, tc.check, got, tc.want)
		}
		if tc.code == proxy.FailureQuota && calls != 0 {
			t.Errorf("the account's problem was checked against the internet")
		}
	}
}

// Mozilla unreachable on a working internet that leaves through a VPN's
// exit is inside_vpn; the answer is asked once for the network, not at
// every retry, and again on another network.
func TestCheckedFailureInsideVPN(t *testing.T) {
	old, oldInside, oldNetwork := netcheck.Check, netcheck.InsideVPN, networkNow
	t.Cleanup(func() { netcheck.Check, netcheck.InsideVPN, networkNow = old, oldInside, oldNetwork })
	insideVPNSeen.at = time.Time{}
	netcheck.Check = func(context.Context) netcheck.Result { return netcheck.Online }
	asked := 0
	netcheck.InsideVPN = func(context.Context) bool { asked++; return true }
	network := "Wi-Fi"
	networkNow = func() (string, bool) { return network, true }

	for range 3 {
		if got := checkedFailure(proxy.FailureUnreachable); got != proxy.FailureInsideVPN {
			t.Fatalf("got %q", got)
		}
	}
	if asked != 1 {
		t.Fatalf("asked %d times on one network", asked)
	}
	// Not for a failure that is not Mozilla's servers being unreachable.
	if got := checkedFailure(proxy.FailureOther); got != proxy.FailureOther {
		t.Fatalf("other: got %q", got)
	}
	network = "Ethernet"
	netcheck.InsideVPN = func(context.Context) bool { asked++; return false }
	if got := checkedFailure(proxy.FailureNoNetwork); got != proxy.FailureUnreachable {
		t.Fatalf("another network: got %q", got)
	}
	if asked != 2 {
		t.Fatalf("another network was not asked again")
	}
}

// Through the user's own proxy, a failure to reach Mozilla names that proxy.
func TestFailureThroughTheUpstreamProxy(t *testing.T) {
	t.Cleanup(func() { _ = resolver.SetUpstreamProxy("", "", "") })
	if err := resolver.SetUpstreamProxy("127.0.0.1:1", "", ""); err != nil {
		t.Fatal(err)
	}
	old := netcheck.Check
	t.Cleanup(func() { netcheck.Check = old })
	netcheck.Check = func(context.Context) netcheck.Result {
		t.Error("the internet outside the proxy says nothing about it")
		return netcheck.Online
	}
	for _, code := range []string{proxy.FailureUnreachable, proxy.FailureNoNetwork, proxy.FailureOther} {
		if got := checkedFailure(code); got != proxy.FailureUpstreamProxy {
			t.Errorf("%s: %s", code, got)
		}
	}
	if got := checkedFailure(proxy.FailureQuota); got != proxy.FailureQuota {
		t.Errorf("quota: %s", got)
	}
}

// QUIC does not go through a SOCKS5 proxy.
func TestEngineTransportThroughTheUpstreamProxy(t *testing.T) {
	cfg := config.Default()
	cfg.Proxy.Transport = "h3"
	if got := engineTransport(cfg); got != "h3" {
		t.Fatalf("direct: %s", got)
	}
	cfg.Network.UpstreamProxy = "127.0.0.1:1080"
	if got := engineTransport(cfg); got != "h3" {
		t.Fatalf("a proxy turned off: %s", got)
	}
	cfg.Network.UpstreamProxyEnabled = true
	if got := engineTransport(cfg); got != "h2" {
		t.Fatalf("through a proxy: %s", got)
	}
}

// The status names the proxy while it is on: filling it in turns it on, and the
// switch turns it off with the address kept.
func TestStatusNamesTheUpstreamProxyWhileOn(t *testing.T) {
	t.Cleanup(func() { _ = resolver.SetUpstreamProxy("", "", "") })
	d, _ := runLazyDaemon(t)
	const address = "127.0.0.1:1080"
	inStatus := func() string {
		t.Helper()
		view, err := d.StatusView()
		if err != nil {
			t.Fatal(err)
		}
		return view.UpstreamProxy
	}
	if got := inStatus(); got != "" {
		t.Fatalf("none set: %q", got)
	}
	next := d.config()
	next.Network.UpstreamProxy = address
	if _, err := d.updateSettings(next, nil); err != nil {
		t.Fatal(err)
	}
	if got := inStatus(); got != address {
		t.Fatalf("filled in: %q", got)
	}
	next = d.config()
	next.Network.UpstreamProxyEnabled = false
	if _, err := d.updateSettings(next, nil); err != nil {
		t.Fatal(err)
	}
	if got := inStatus(); got != "" {
		t.Fatalf("off: %q", got)
	}
	if got := d.config().Network.UpstreamProxy; got != address {
		t.Fatalf("off lost the address: %q", got)
	}
}

// The switch decides, while the address stays set.
func TestConfigureAPIRelayUsesTheUpstreamProxyOnlyWhileOn(t *testing.T) {
	t.Cleanup(func() { _ = resolver.SetUpstreamProxy("", "", "") })
	const address = "127.0.0.1:1080"
	for _, on := range []bool{true, false, true} {
		n := config.Network{UpstreamProxy: address, UpstreamProxyEnabled: on}
		if err := configureAPIRelay(n); err != nil {
			t.Fatal(err)
		}
		want := ""
		if on {
			want = address
		}
		if got := resolver.UpstreamProxy(); got != want {
			t.Fatalf("on = %v: %q", on, got)
		}
	}
}
