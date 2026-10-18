//go:build windows

package desktop

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/windows/registry"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/service"
)

// useTestProxyKeys points the system proxy code at temporary keys under
// HKCU\Software, so the user's real proxy setting is never touched.
func useTestProxyKeys(t *testing.T) registry.Key {
	t.Helper()
	base := fmt.Sprintf(`Software\FirefoxVPNTest-%d`, time.Now().UnixNano())
	oldSettings, oldBackup, oldAnnounce := internetSettingsKey, backupKey, announceProxyChange
	internetSettingsKey, backupKey = base+`\Internet Settings`, base+`\PreviousProxy`
	announceProxyChange = func() {}
	k, _, err := registry.CreateKey(registry.CURRENT_USER, internetSettingsKey, registry.ALL_ACCESS)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		k.Close()
		_ = registry.DeleteKey(registry.CURRENT_USER, internetSettingsKey)
		_ = registry.DeleteKey(registry.CURRENT_USER, backupKey)
		_ = registry.DeleteKey(registry.CURRENT_USER, base)
		internetSettingsKey, backupKey, announceProxyChange = oldSettings, oldBackup, oldAnnounce
	})
	return k
}

func setting(t *testing.T) proxySetting {
	t.Helper()
	k, err := registry.OpenKey(registry.CURRENT_USER, internetSettingsKey, registry.QUERY_VALUE)
	if err != nil {
		t.Fatal(err)
	}
	defer k.Close()
	return readProxySetting(k)
}

func TestSystemProxySetAndRestore(t *testing.T) {
	k := useTestProxyKeys(t)
	corp := proxySetting{enabled: true, server: "corp.example:8080", override: "*.corp.example", script: "http://corp.example/proxy.pac"}
	if err := writeProxySetting(k, corp); err != nil {
		t.Fatal(err)
	}

	// Set replaces the user's proxy and setup script, which Windows would
	// use first.
	if err := setSystemProxy("127.0.0.1:10810"); err != nil {
		t.Fatal(err)
	}
	if p := setting(t); !p.enabled || p.server != "127.0.0.1:10810" || !strings.Contains(p.override, "<local>") || p.script != "" {
		t.Fatalf("after set: %+v", p)
	}
	if err := setSystemProxy("127.0.0.1:10810"); err != nil { // again: keeps the first backup
		t.Fatal(err)
	}
	if err := restoreSystemProxy("127.0.0.1:10810"); err != nil {
		t.Fatal(err)
	}
	if p := setting(t); p != corp {
		t.Fatalf("the previous setting must come back: %+v", p)
	}

	// A proxy the user chose meanwhile stays.
	if err := setSystemProxy("127.0.0.1:10810"); err != nil {
		t.Fatal(err)
	}
	_ = k.SetStringValue("ProxyServer", "other.example:3128")
	if err := restoreSystemProxy("127.0.0.1:10810"); err != nil {
		t.Fatal(err)
	}
	if p := setting(t); p.server != "other.example:3128" {
		t.Fatalf("the user's own proxy was replaced: %+v", p)
	}

	// Clear turns any system proxy off, setup script included.
	_ = k.SetStringValue("AutoConfigURL", "http://corp.example/proxy.pac")
	if err := clearSystemProxy(); err != nil {
		t.Fatal(err)
	}
	if p := setting(t); p.enabled || p.script != "" {
		t.Fatalf("after clear: %+v", p)
	}
}

func trayStatus(phase, mode string) *service.TrayStatus {
	st := &service.TrayStatus{SystemProxy: mode}
	st.State.Phase = phase
	st.Proxy = &service.TrayProxy{Listen: "0.0.0.0:10810"}
	return st
}

// Set is carried out only while the proxy runs, and undone when it stops
// or the service is gone; clear acts once.
func TestSystemProxyModes(t *testing.T) {
	k := useTestProxyKeys(t)
	user := proxySetting{enabled: true, server: "user.example:3128"}
	if err := writeProxySetting(k, user); err != nil {
		t.Fatal(err)
	}
	var sync systemProxySync

	// While the proxy starts, set changes nothing yet.
	sync.update(trayStatus("starting", config.SystemProxySet))
	if p := setting(t); p != user || sync.active() {
		t.Fatalf("set before the proxy runs: %+v", p)
	}
	// The tray refreshes every few seconds; the setting must stay.
	for i := 0; i < 3; i++ {
		sync.update(trayStatus("running", config.SystemProxySet))
		if p := setting(t); p.server != "127.0.0.1:10810" || !p.enabled || !sync.active() {
			t.Fatalf("set while running, refresh %d: %+v", i+1, p)
		}
	}
	sync.update(trayStatus("error", config.SystemProxySet))
	if p := setting(t); p != user || sync.active() {
		t.Fatalf("the proxy stopped: the previous setting comes back: %+v", p)
	}
	sync.update(trayStatus("running", config.SystemProxySet))
	sync.update(nil)
	if p := setting(t); p != user || sync.active() {
		t.Fatalf("the service is gone: restored: %+v", p)
	}
	sync.update(trayStatus("running", config.SystemProxySet))
	sync.clear()
	if p := setting(t); p != user || sync.active() {
		t.Fatalf("the host exits: restored: %+v", p)
	}

	// Switching from set to clear restores this program's setting, then
	// turns the system proxy off.
	sync.update(trayStatus("running", config.SystemProxySet))
	sync.update(trayStatus("running", config.SystemProxyClear))
	if p := setting(t); p.enabled || p.server != "user.example:3128" || sync.active() {
		t.Fatalf("clear turns the system proxy off: %+v", p)
	}
	// Clear acts once: a proxy set by hand afterwards stays.
	_ = writeProxySetting(k, user)
	for i := 0; i < 3; i++ {
		sync.update(trayStatus("running", config.SystemProxyClear))
	}
	if p := setting(t); p != user {
		t.Fatalf("clear must not fight a later setting: %+v", p)
	}

	// A setting left behind by an earlier copy is restored when not wanted.
	_ = setSystemProxy("127.0.0.1:10810")
	var fresh systemProxySync
	fresh.update(trayStatus("starting", config.SystemProxySet))
	if p := setting(t); p != user {
		t.Fatalf("a leftover setting must be restored: %+v", p)
	}
	// A host that starts in clear turns the system proxy off.
	var clearing systemProxySync
	clearing.update(trayStatus("starting", config.SystemProxyClear))
	if p := setting(t); p.enabled {
		t.Fatalf("a host starting in clear turns the system proxy off: %+v", p)
	}
}
