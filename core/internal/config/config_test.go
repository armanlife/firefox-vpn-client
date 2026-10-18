package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLoadCreatesDefaultConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data", FileName)
	cfg, created, err := Load(path)
	if err != nil || !created {
		t.Fatalf("expected a created default config, got created=%v err=%v", created, err)
	}
	if cfg.Proxy.Listen != DefaultProxyListen || cfg.Dashboard.Listen != DefaultDashboardListen || !cfg.Dashboard.Enabled {
		t.Fatalf("unexpected defaults: %+v", cfg)
	}
	if cfg.Accounts.SwitchThresholdPercent != 90 || cfg.Accounts.QuotaCheckInterval.Duration() != 30*time.Minute {
		t.Fatalf("unexpected account defaults: %+v", cfg.Accounts)
	}

	again, created, err := Load(path)
	if err != nil || created {
		t.Fatalf("expected the saved config to load, got created=%v err=%v", created, err)
	}
	if again.Proxy.Listen != cfg.Proxy.Listen || again.Proxy.Transport != cfg.Proxy.Transport {
		t.Fatalf("round trip changed values: %+v vs %+v", again.Proxy, cfg.Proxy)
	}
}

func TestLoadKeepsDefaultsForOmittedFields(t *testing.T) {
	path := filepath.Join(t.TempDir(), FileName)
	if err := os.WriteFile(path, []byte(`{"proxy":{"listen":"127.0.0.1:2080","country":"DE"},"accounts":{"switch_threshold_percent":80}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, _, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Proxy.Listen != "127.0.0.1:2080" || cfg.Proxy.Country != "DE" || cfg.Accounts.SwitchThresholdPercent != 80 {
		t.Fatalf("explicit values not applied: %+v", cfg)
	}
	if cfg.Proxy.Transport != "h2" || cfg.Accounts.QuotaCheckInterval.Duration() != DefaultQuotaCheckInterval {
		t.Fatalf("defaults not kept for omitted fields: %+v", cfg)
	}
	if cfg.SystemProxy.Mode != SystemProxyClear {
		t.Fatalf("system_proxy.mode defaults to clear (proxy only), got %q", cfg.SystemProxy.Mode)
	}
	if cfg.Proxy.IdleSleep.Duration() != DefaultIdleSleep {
		t.Fatalf("idle sleep defaults to 15 minutes, got %s", cfg.Proxy.IdleSleep.Duration())
	}
	if len(cfg.DNS.Servers) != len(DefaultDNSServers) || !cfg.DNS.FallbackToSystem {
		t.Fatalf("a config without a dns section must use the system resolver with fallback: %+v", cfg.DNS)
	}
}

func TestLoadRejectsInvalidConfig(t *testing.T) {
	for name, body := range map[string]string{
		"country and server":     `{"proxy":{"country":"US","server":"us.example:443"}}`,
		"bad transport":          `{"proxy":{"transport":"h1"}}`,
		"threshold too high":     `{"accounts":{"switch_threshold_percent":120}}`,
		"interval too short":     `{"accounts":{"quota_check_interval":"5s"}}`,
		"duration as number":     `{"proxy":{"idle_sleep":20}}`,
		"duplicate account":      `{"accounts":{"order":[{"id":"a","enabled":true},{"id":"a","enabled":true}]}}`,
		"user without hash":      `{"dashboard":{"username":"admin"}}`,
		"bad dashboard listen":   `{"dashboard":{"listen":"10820"}}`,
		"bad dns server":         `{"dns":{"servers":["dns.google"]}}`,
		"unknown region":         `{"routing":{"region":"xx"}}`,
		"pac system proxy":       `{"system_proxy":{"mode":"pac"}}`,
		"unchanged system proxy": `{"system_proxy":{"mode":"unchanged"}}`,
		"empty system proxy":     `{"system_proxy":{"mode":""}}`,
	} {
		path := filepath.Join(t.TempDir(), FileName)
		if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, _, err := Load(path); err == nil {
			t.Errorf("%s: expected an error", name)
		}
	}
}

func TestDefaultDataDirIsNextToExecutable(t *testing.T) {
	dir, err := DefaultDataDir()
	if err != nil {
		t.Fatal(err)
	}
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	if want := filepath.Join(filepath.Dir(exe), DataDirName); dir != want {
		t.Fatalf("expected %s, got %s", want, dir)
	}
}

func TestCheckWritableCreatesFolder(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "nested", "data")
	if err := CheckWritable(dir); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 0 {
		t.Fatalf("expected an empty writable folder, got %v %v", entries, err)
	}
	if err := CheckWritable(filepath.Join(dir, "missing-parent-file", strings.Repeat("x", 3))); err != nil {
		t.Fatalf("nested creation should succeed: %v", err)
	}
}

func TestLoadDropsRemovedSettingsAndNormalizesRecommended(t *testing.T) {
	path := filepath.Join(t.TempDir(), FileName)
	if err := os.WriteFile(path, []byte(`{"proxy":{"country":"REC","firefox_version":"150.0"}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	var warnings []string
	Warn = func(m string) { warnings = append(warnings, m) }
	defer func() { Warn = nil }()
	cfg, _, err := Load(path)
	if err != nil {
		t.Fatalf("an unknown setting must not stop loading: %v", err)
	}
	if cfg.Proxy.Country != "" {
		t.Fatalf("REC is the recommended location (empty country), got %q", cfg.Proxy.Country)
	}
	if len(warnings) != 1 || !strings.Contains(warnings[0], "firefox_version") {
		t.Fatalf("warnings = %v", warnings)
	}
	data, _ := os.ReadFile(path)
	if strings.Contains(string(data), "firefox_version") || strings.Contains(string(data), `"REC"`) {
		t.Fatalf("the file must be rewritten: %s", data)
	}
	if _, _, err := Load(path); err != nil || len(warnings) != 1 {
		t.Fatalf("a clean file loads without warnings: %v %v", err, warnings)
	}
}

// The system proxy has two modes, set and clear (the default: proxy
// only); anything else is refused with the accepted values.
func TestSystemProxyModes(t *testing.T) {
	cfg := Default()
	if cfg.SystemProxy.Mode != SystemProxyClear {
		t.Fatalf("default system proxy mode %q", cfg.SystemProxy.Mode)
	}
	for _, mode := range []string{SystemProxySet, SystemProxyClear} {
		cfg.SystemProxy.Mode = mode
		if err := cfg.Validate(); err != nil {
			t.Errorf("mode %q: %v", mode, err)
		}
	}
	for _, mode := range []string{"pac", "unchanged", "", "Set"} {
		cfg.SystemProxy.Mode = mode
		err := cfg.Validate()
		if err == nil || !strings.Contains(err.Error(), "system_proxy.mode") || !strings.Contains(err.Error(), `"set" or "clear"`) {
			t.Errorf("mode %q must be refused naming the accepted values: %v", mode, err)
		}
	}
}

// Routing defaults to the Iran region with its preset rules in the Direct
// list and the Chocolate4U lists; an explicit empty region means none.
func TestRoutingRegionDefaultsAndValues(t *testing.T) {
	cfg := Default()
	if cfg.Routing.Enabled || cfg.Routing.Region != "ir" || strings.Join(cfg.Routing.Direct, " ") != "geosite:ir ext:iran.dat:ir geoip:ir geoip:private" {
		t.Fatalf("routing defaults: %+v", cfg.Routing)
	}
	for _, u := range []string{cfg.Routing.GeoSiteURL, cfg.Routing.GeoIPURL} {
		if !strings.Contains(u, "Chocolate4U/Iran-v2ray-rules") {
			t.Errorf("default list %s", u)
		}
	}
	for _, region := range []string{"ir", "cn", "ru", "af", "tr", "id", "br", ""} {
		cfg.Routing.Region = region
		if err := cfg.Validate(); err != nil {
			t.Errorf("region %q: %v", region, err)
		}
	}
	cfg.Routing.Region = "IR"
	if err := cfg.Validate(); err == nil || !strings.Contains(err.Error(), "routing.region") {
		t.Errorf("an unknown region must name the field: %v", err)
	}

	path := filepath.Join(t.TempDir(), FileName)
	if err := os.WriteFile(path, []byte(`{"routing":{"enabled":true,"region":""}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	loaded, _, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Routing.Region != "" || !loaded.Routing.Enabled {
		t.Fatalf("an explicit empty region is kept: %+v", loaded.Routing)
	}
	// No Direct list in the file: the region's presets, not Iran's.
	if strings.Join(loaded.Routing.Direct, " ") != "geoip:private" {
		t.Fatalf("direct of a file without one: %v", loaded.Routing.Direct)
	}

	// Version 1 added the presets by itself: they move into the list once,
	// before the user's own rules.
	if err := os.WriteFile(path, []byte(`{"version":1,"routing":{"enabled":true,"region":"tr","direct":["domain:my.example"]}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if loaded, _, err = Load(path); err != nil {
		t.Fatal(err)
	}
	if strings.Join(loaded.Routing.Direct, " ") != "domain:tr geoip:tr geoip:private domain:my.example" {
		t.Fatalf("version 1 direct: %v", loaded.Routing.Direct)
	}
	if again, _, err := Load(path); err != nil || strings.Join(again.Routing.Direct, " ") != strings.Join(loaded.Routing.Direct, " ") {
		t.Fatalf("the move happens once: %v %v", again.Routing.Direct, err)
	}
}

func TestDefaultDataDirFollowsTheApp(t *testing.T) {
	env := map[string]string{"LOCALAPPDATA": `C:\Users\u\AppData\Local`, "HOME": "/home/u"}
	getenv := func(k string) string { return env[k] }
	files := map[string]bool{}
	exists := func(p string) bool { return files[filepath.Base(p)] }
	dir := filepath.Join("opt", "vpn")

	// On its own: user-data beside the core (not Flutter's "data").
	if got := defaultDataDirFor(dir, "linux", getenv, exists); got != filepath.Join(dir, "user-data") {
		t.Fatalf("alone: %s", got)
	}
	// Beside the desktop app on Windows: user-data beside both.
	files["firefox-vpn.exe"] = true
	if got := defaultDataDirFor(dir, "windows", getenv, exists); got != filepath.Join(dir, "user-data") {
		t.Fatalf("beside the app on Windows: %s", got)
	}
	// On macOS: the app's folder in the user's data location.
	files["firefox_vpn"] = true
	if got := defaultDataDirFor(dir, "darwin", getenv, exists); got != filepath.Join("/home/u", "Library", "Application Support", "Firefox VPN Client") {
		t.Fatalf("beside the app on macOS: %s", got)
	}
	// A portable app keeps user-data beside it.
	files["portable"] = true
	if got := defaultDataDirFor(dir, "darwin", getenv, exists); got != filepath.Join(dir, "user-data") {
		t.Fatalf("portable: %s", got)
	}
}

func TestBesideApp(t *testing.T) {
	files := map[string]bool{}
	exists := func(p string) bool { return files[filepath.Base(p)] }
	if besideApp("dir", exists) {
		t.Fatal("a core on its own is not beside the app")
	}
	for _, name := range []string{"firefox-vpn.exe", "firefox_vpn"} {
		files = map[string]bool{name: true}
		if !besideApp("dir", exists) {
			t.Fatalf("beside %s", name)
		}
	}
}
