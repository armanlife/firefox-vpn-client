package service

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/routing"
)

// The phone's VPN refuses at once what Mozilla would refuse, unless the
// routing sends it directly.
func TestTunnelAllowsMozillaPortsAndDirectDestinations(t *testing.T) {
	d := newTestDaemon(t)
	for port, want := range map[string]bool{"443": true, "80": true, "8443": true, "5222": false, "22": false} {
		if got := d.TunnelAllows("chat.example", port); got != want {
			t.Errorf("port %s: %t", port, got)
		}
	}
	// Git over SSH to GitHub goes to its SSH server on port 443.
	if !d.TunnelAllows("github.com", "22") || !d.TunnelAllows("GitHub.com", "22") {
		t.Error("GitHub's SSH is refused")
	}
	// Android's notifications: Google's push server on its own ports.
	if !d.TunnelAllows("mtalk.google.com", "5228") || !d.TunnelAllows("alt1-mtalk.google.com", "5230") {
		t.Error("Google's push server is refused")
	}
	writeTestGeoIP(t, d, map[string][]string{"private": {"10.0.0.0/8"}})
	d.applyRouting(config.Routing{Enabled: true, Direct: []string{"domain:bank.test"}})
	if d.currentRouter() == nil {
		t.Fatal("the routing did not load")
	}
	if !d.TunnelAllows("www.bank.test", "8081") {
		t.Fatal("a direct destination may use any port")
	}
	if d.TunnelAllows("chat.example", "5222") {
		t.Fatal("a proxied destination keeps Mozilla's ports")
	}
}

// A printer or a shared folder is reachable on its own port with routing off.
func TestTunnelAllowsTheLocalNetworkOnAnyPort(t *testing.T) {
	d := newTestDaemon(t)
	for _, host := range []string{"192.168.1.20", "10.0.0.5", "fd00::5"} {
		if !d.TunnelAllows(host, "9100") {
			t.Errorf("%s:9100 is refused", host)
		}
	}
	if d.TunnelAllows("8.8.8.8", "9100") {
		t.Error("an internet address keeps Mozilla's ports")
	}
}

// What leads nowhere is refused at once, whatever the port or the routing; DNS
// is answered by the proxy, whichever server it is sent to.
func TestTunnelRefusesDeadEnds(t *testing.T) {
	d := newTestDaemon(t)
	writeTestGeoIP(t, d, map[string][]string{"private": {"10.0.0.0/8"}})
	d.applyRouting(config.Routing{Enabled: true, Direct: []string{"geoip:private"}})
	for _, host := range []string{"10.10.34.36", "2001:4188:2:600:10:10:34:36", "172.19.0.2", "198.18.0.7"} {
		if d.TunnelAllows(host, "443") {
			t.Errorf("TCP to %s is allowed", host)
		}
		if d.TunnelAllowsUDP(host, "3478") {
			t.Errorf("UDP to %s is allowed", host)
		}
	}
	for _, host := range []string{"8.8.8.8", "172.19.0.2"} {
		if !d.TunnelAllows(host, "53") || !d.TunnelAllowsUDP(host, "53") {
			t.Errorf("DNS to %s is refused", host)
		}
	}
	for _, host := range []string{"192.168.1.5", "224.0.0.251", "ff02::fb"} {
		if d.TunnelAllowsUDP(host, "3478") {
			t.Errorf("UDP to %s is allowed", host)
		}
	}
	if !d.TunnelAllowsUDP("1.2.3.4", "3478") {
		t.Error("UDP to an address on the internet is refused")
	}
}

// The region's app list is read only while routing is on.
func TestDirectAppsFollowTheRouting(t *testing.T) {
	d := newTestDaemon(t)
	if err := writeTestFile(d.paths.RoutingDir, routing.AppListFile("ir"), "cab.snapp.passenger\ncom.digikala\n"); err != nil {
		t.Fatal(err)
	}
	d.mu.Lock()
	d.cfg.Routing.Enabled, d.cfg.Routing.Region = true, "ir"
	d.mu.Unlock()
	if got := d.DirectApps(); len(got) != 2 {
		t.Fatalf("apps %v", got)
	}
	d.mu.Lock()
	d.cfg.Routing.Enabled = false
	d.mu.Unlock()
	if got := d.DirectApps(); got != nil {
		t.Fatalf("routing off, apps %v", got)
	}
}

// A network change voids the last test and, connected, reconnects.
func TestNetworkChangeReconnects(t *testing.T) {
	d, f := runLazyDaemon(t)
	view, _ := d.StatusView()
	if err := lazyEcho(t, view.Proxy.Listen, "before"); err != nil {
		t.Fatal(err)
	}
	before := f.connects.Load()
	d.NetworkChanged(true)
	view, _ = d.StatusView()
	if view.NetworkChangedAt.IsZero() || time.Since(view.NetworkChangedAt) > time.Minute {
		t.Fatalf("network change time %v", view.NetworkChangedAt)
	}
	if err := lazyEcho(t, view.Proxy.Listen, "after"); err != nil {
		t.Fatalf("after the change: %v", err)
	}
	if f.passes.Load() != 1 {
		t.Fatalf("passes %d; a reconnect keeps the pass", f.passes.Load())
	}
	if f.connects.Load() <= before {
		t.Fatal("no connection after the change")
	}
	if view.NoNetwork {
		t.Fatal("a network is connected")
	}

	// No network: the status says so at once.
	t.Cleanup(func() { d.NetworkChanged(true) })
	d.NetworkChanged(false)
	if view, _ = d.StatusView(); !view.NoNetwork {
		t.Fatal("no_network not reported")
	}
}

func writeTestFile(dir, name, content string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600)
}

// The VPN's UDP goes through Mozilla on its ports, without QUIC unless the
// setting asks for it; a direct destination may use any port.
func TestTunnelAllowsUDP(t *testing.T) {
	d := newTestDaemon(t)
	for port, want := range map[string]bool{"3478": true, "50000": true, "443": false, "19302": false, "53": true} {
		if got := d.TunnelAllowsUDP("peer.example", port); got != want {
			t.Errorf("port %s: %t", port, got)
		}
	}
	d.mu.Lock()
	d.cfg.Tun.QUIC = true
	d.mu.Unlock()
	if !d.TunnelAllowsUDP("peer.example", "443") {
		t.Error("tun.quic did not let QUIC through")
	}
	writeTestGeoIP(t, d, map[string][]string{"private": {"10.0.0.0/8"}})
	d.applyRouting(config.Routing{Enabled: true, Direct: []string{"domain:bank.test"}})
	if !d.TunnelAllowsUDP("www.bank.test", "19302") {
		t.Fatal("a direct destination may use any port")
	}
}
