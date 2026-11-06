package config

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
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
	if cfg.Accounts.SwitchThresholdPercent != 95 {
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
	if cfg.Proxy.Transport != "h2" {
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

// A relay set before network.api_relay_enabled existed stays in use; one
// turned off keeps its address.
func TestRelayEnabledByDefault(t *testing.T) {
	path := filepath.Join(t.TempDir(), FileName)
	if err := os.WriteFile(path, []byte(`{"network":{"api_relay":"https://relay.example/"}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, _, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Network.APIRelayInUse() != "https://relay.example/" {
		t.Fatalf("a relay without the switch must stay in use: %+v", cfg.Network)
	}
	cfg.Network.APIRelayEnabled = false
	if cfg.Network.APIRelayInUse() != "" || cfg.Network.APIRelay == "" {
		t.Fatalf("turned off: %+v", cfg.Network)
	}
}

func TestLoadRejectsInvalidConfig(t *testing.T) {
	for name, body := range map[string]string{
		"country and server":     `{"proxy":{"country":"US","server":"us.example:443"}}`,
		"bad transport":          `{"proxy":{"transport":"h4"}}`,
		"bad ip version":         `{"proxy":{"ip_version":"ipv5"}}`,
		"mtu too small":          `{"tun":{"mtu":576}}`,
		"threshold too high":     `{"accounts":{"switch_threshold_percent":120}}`,
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

// allow_locked is ignored: a file that carries it loads without a warning
// and is rewritten without it.
func TestLoadIgnoresAllowLocked(t *testing.T) {
	path := filepath.Join(t.TempDir(), FileName)
	if err := os.WriteFile(path, []byte(`{"proxy":{"country":"GB","allow_locked":true}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	var warnings []string
	Warn = func(m string) { warnings = append(warnings, m) }
	defer func() { Warn = nil }()
	cfg, _, err := Load(path)
	if err != nil || len(warnings) != 0 {
		t.Fatalf("allow_locked must still load: %v %v", err, warnings)
	}
	if cfg.Proxy.AllowLocked || cfg.Proxy.Country != "GB" {
		t.Fatalf("proxy = %+v", cfg.Proxy)
	}
	data, _ := os.ReadFile(path)
	if strings.Contains(string(data), "allow_locked") {
		t.Fatalf("the file must be rewritten without allow_locked: %s", data)
	}
}

// The connection modes are set, clear (the default: proxy only), and tun;
// anything else is refused with the accepted values.
func TestSystemProxyModes(t *testing.T) {
	cfg := Default()
	if cfg.SystemProxy.Mode != SystemProxyClear {
		t.Fatalf("default system proxy mode %q", cfg.SystemProxy.Mode)
	}
	for _, mode := range []string{SystemProxySet, SystemProxyClear, SystemProxyTun} {
		cfg.SystemProxy.Mode = mode
		if err := cfg.Validate(); err != nil {
			t.Errorf("mode %q: %v", mode, err)
		}
	}
	for _, mode := range []string{"pac", "unchanged", "", "Set"} {
		cfg.SystemProxy.Mode = mode
		err := cfg.Validate()
		if err == nil || !strings.Contains(err.Error(), "system_proxy.mode") || !strings.Contains(err.Error(), `"set", "clear", or "tun"`) {
			t.Errorf("mode %q must be refused naming the accepted values: %v", mode, err)
		}
	}
}

// The programs that skip the VPN start empty; a file's are kept by their
// file name, once each, and a path in one is refused.
func TestTunProgramsAreFileNames(t *testing.T) {
	if p := Default().Tun.Programs; p == nil || len(p) != 0 {
		t.Fatalf("default tun.programs %#v", p)
	}
	got := CleanTunPrograms([]TunProgram{
		{Name: ` C:\Games\Steam\steam.exe `},
		{Name: "STEAM.EXE", UDPOnly: true},
		{Name: "/usr/bin/telegram-desktop", UDPOnly: true},
		{Name: "  "},
	})
	want := []TunProgram{{Name: "steam.exe", Path: `C:\Games\Steam\steam.exe`}, {Name: "telegram-desktop", UDPOnly: true, Path: "/usr/bin/telegram-desktop"}}
	if !slices.Equal(got, want) {
		t.Fatalf("cleaned %+v, want %+v", got, want)
	}
	if got := CleanTunPrograms(nil); got == nil || len(got) != 0 {
		t.Fatalf("cleaned nil to %#v", got)
	}

	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{"tun":{"programs":[{"name":"D:\\Apps\\Discord.exe","udp_only":true},{"name":"discord.exe"}]}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, _, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if want := []TunProgram{{Name: "Discord.exe", UDPOnly: true, Path: `D:\Apps\Discord.exe`}}; !slices.Equal(cfg.Tun.Programs, want) {
		t.Fatalf("loaded %+v, want %+v", cfg.Tun.Programs, want)
	}
	// A pattern with * or ? is a name too.
	cfg.Tun.Programs = []TunProgram{{Name: "steam*", UDPOnly: true}, {Name: "tele?ram.exe"}}
	if err := cfg.Validate(); err != nil {
		t.Errorf("patterns: %v", err)
	}
	for _, bad := range []TunProgram{{Name: `a\b.exe`}, {Name: ""}, {Name: strings.Repeat("x", 256)}} {
		cfg.Tun.Programs = []TunProgram{bad}
		if err := cfg.Validate(); err == nil || !strings.Contains(err.Error(), "tun.programs") {
			t.Errorf("%q: %v", bad.Name, err)
		}
	}
	cfg.Tun.Programs = make([]TunProgram, MaxTunPrograms+1)
	for i := range cfg.Tun.Programs {
		cfg.Tun.Programs[i].Name = fmt.Sprintf("p%d.exe", i)
	}
	if err := cfg.Validate(); err == nil {
		t.Error("more programs than allowed were taken")
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
	files["arman-vpn.exe"] = true
	if got := defaultDataDirFor(dir, "windows", getenv, exists); got != filepath.Join(dir, "user-data") {
		t.Fatalf("beside the app on Windows: %s", got)
	}
	// On macOS: the app's folder in the user's data location.
	files["Arman VPN"] = true
	if got := defaultDataDirFor(dir, "darwin", getenv, exists); got != filepath.Join("/home/u", "Library", "Application Support", "Arman VPN") {
		t.Fatalf("beside the app on macOS: %s", got)
	}
	// A portable app keeps user-data beside it.
	files["portable"] = true
	if got := defaultDataDirFor(dir, "darwin", getenv, exists); got != filepath.Join(dir, "user-data") {
		t.Fatalf("portable: %s", got)
	}
}

func TestAppDir(t *testing.T) {
	// Files by their full path, so the parent folder counts.
	files := map[string]bool{}
	exists := func(p string) bool { return files[p] }
	app := filepath.Join("opt", "Arman VPN")
	core := filepath.Join(app, "core")
	if got := appDir(app, exists); got != "" {
		t.Fatalf("a core on its own belongs to %q", got)
	}
	for _, name := range []string{"arman-vpn.exe", "arman-vpn", "Arman VPN"} {
		files = map[string]bool{filepath.Join(app, name): true}
		if got := appDir(app, exists); got != app {
			t.Fatalf("beside %s: %q", name, got)
		}
		// In the app's core folder: the app's folder.
		if got := appDir(core, exists); got != app {
			t.Fatalf("in the core folder of %s: %q", name, got)
		}
	}
	// The parent counts only from a folder named core.
	files = map[string]bool{filepath.Join(app, "arman-vpn.exe"): true}
	if got := appDir(filepath.Join(app, "tools"), exists); got != "" {
		t.Fatalf("a core in another folder belongs to %q", got)
	}
	// The data folder of a core in the core folder is the app's.
	if got := defaultDataDirFor(core, "windows", func(string) string { return "" }, exists); got != filepath.Join(app, "user-data") {
		t.Fatalf("data folder from the core folder: %s", got)
	}
}

// A config.json that cannot be read (empty after a power cut, or broken
// JSON) no longer stops the program: it starts with the defaults and keeps
// the broken file beside it.
func TestLoadRecoversFromACorruptFile(t *testing.T) {
	for name, content := range map[string]string{"empty": "", "cut short": `{"proxy": {"listen": "127.0`} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), FileName)
			if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
				t.Fatal(err)
			}
			var warned string
			defer func(old func(string)) { Warn = old }(Warn)
			Warn = func(s string) { warned = s }
			cfg, _, err := Load(path)
			if err != nil {
				t.Fatalf("a corrupt config must not stop the program: %v", err)
			}
			if cfg.Proxy.Listen != Default().Proxy.Listen {
				t.Fatalf("want the defaults, got %+v", cfg.Proxy)
			}
			if !strings.Contains(warned, "default settings") {
				t.Fatalf("no warning: %q", warned)
			}
			kept, err := os.ReadFile(path + ".corrupt")
			if content == "" {
				if err == nil {
					t.Fatal("an empty file needs no copy")
				}
			} else if err != nil || string(kept) != content {
				t.Fatalf("the broken file must be kept: %v %q", err, kept)
			}
			if _, _, err := Load(path); err != nil {
				t.Fatalf("the rewritten file must load: %v", err)
			}
		})
	}
}

func TestValidateUpstreamProxy(t *testing.T) {
	const listen = "127.0.0.1:10810"
	for _, tc := range []struct {
		name string
		n    Network
		ok   bool
	}{
		{"none", Network{}, true},
		{"address", Network{UpstreamProxy: "127.0.0.1:10808"}, true},
		{"name", Network{UpstreamProxy: "proxy.example:1080"}, true},
		{"ipv6", Network{UpstreamProxy: "[2001:db8::1]:1080"}, true},
		{"login", Network{UpstreamProxy: "10.0.0.1:1080", UpstreamProxyUsername: "u", UpstreamProxyPassword: "p"}, true},
		// Another machine on this port is another proxy.
		{"another machine's same port", Network{UpstreamProxy: "10.0.0.1:10810"}, true},
		{"no port", Network{UpstreamProxy: "127.0.0.1"}, false},
		{"bad port", Network{UpstreamProxy: "127.0.0.1:70000"}, false},
		{"port zero", Network{UpstreamProxy: "127.0.0.1:0"}, false},
		{"no host", Network{UpstreamProxy: ":1080"}, false},
		{"username alone", Network{UpstreamProxy: "127.0.0.1:1080", UpstreamProxyUsername: "u"}, false},
		{"password alone", Network{UpstreamProxy: "127.0.0.1:1080", UpstreamProxyPassword: "p"}, false},
		{"long login", Network{UpstreamProxy: "127.0.0.1:1080", UpstreamProxyUsername: strings.Repeat("u", 256), UpstreamProxyPassword: "p"}, false},
		{"its own port", Network{UpstreamProxyEnabled: true, UpstreamProxy: "127.0.0.1:10810"}, false},
		{"its own port, by name", Network{UpstreamProxyEnabled: true, UpstreamProxy: "localhost:10810"}, false},
		{"its own port, any address", Network{UpstreamProxyEnabled: true, UpstreamProxy: "0.0.0.0:10810"}, false},
		// While off it blocks nothing, such as moving this program to that port.
		{"its own port, off", Network{UpstreamProxy: "127.0.0.1:10810"}, true},
		{"no port, off", Network{UpstreamProxy: "127.0.0.1"}, false},
	} {
		if err := ValidateUpstreamProxy(tc.n, listen); (err == nil) != tc.ok {
			t.Errorf("%s: %v", tc.name, err)
		}
	}
}

func TestUpstreamProxyInUse(t *testing.T) {
	n := Network{UpstreamProxy: "127.0.0.1:1080"}
	if got := n.UpstreamProxyInUse(); got != "" {
		t.Errorf("off: %q", got)
	}
	n.UpstreamProxyEnabled = true
	if got := n.UpstreamProxyInUse(); got != "127.0.0.1:1080" {
		t.Errorf("on: %q", got)
	}
}

func TestSettleUpstreamProxy(t *testing.T) {
	const a, b = "127.0.0.1:1080", "127.0.0.1:1081"
	for _, tc := range []struct {
		name       string
		prev, next Network
		on         bool
	}{
		{"filled in", Network{}, Network{UpstreamProxy: a}, true},
		{"emptied", Network{UpstreamProxy: a, UpstreamProxyEnabled: true}, Network{UpstreamProxyEnabled: true}, false},
		{"on without an address", Network{}, Network{UpstreamProxyEnabled: true}, false},
		{"turned off", Network{UpstreamProxy: a, UpstreamProxyEnabled: true}, Network{UpstreamProxy: a}, false},
		{"turned on", Network{UpstreamProxy: a}, Network{UpstreamProxy: a, UpstreamProxyEnabled: true}, true},
		{"edited while off", Network{UpstreamProxy: a}, Network{UpstreamProxy: b}, false},
		{"edited while on", Network{UpstreamProxy: a, UpstreamProxyEnabled: true}, Network{UpstreamProxy: b, UpstreamProxyEnabled: true}, true},
	} {
		if got := SettleUpstreamProxy(tc.prev, tc.next); got.UpstreamProxyEnabled != tc.on {
			t.Errorf("%s: on = %v", tc.name, got.UpstreamProxyEnabled)
		}
	}
	got := SettleUpstreamProxy(Network{}, Network{UpstreamProxy: " socks5://127.0.0.1:1080/ ", UpstreamProxyUsername: " u ", UpstreamProxyPassword: " p "})
	if got.UpstreamProxy != a || got.UpstreamProxyUsername != "u" || got.UpstreamProxyPassword != "p" {
		t.Errorf("not cleaned: %+v", got)
	}
}

func TestCleanUpstreamProxy(t *testing.T) {
	for in_, want := range map[string]string{
		"":                         "",
		"127.0.0.1:1080":           "127.0.0.1:1080",
		"  127.0.0.1:1080\n":       "127.0.0.1:1080",
		"127. 0.0.1 : 1080":        "127.0.0.1:1080",
		"socks5://127.0.0.1:1080/": "127.0.0.1:1080",
		" socks5h://[::1]:1080 ":   "[::1]:1080",
	} {
		if got := CleanUpstreamProxy(in_); got != want {
			t.Errorf("%q: %q, want %q", in_, got, want)
		}
	}
}

func TestIPVersionDefaultsToAuto(t *testing.T) {
	if got := Default().Proxy.IPVersion; got != "auto" {
		t.Fatalf("default ip_version = %q, want auto", got)
	}
	for _, v := range []string{"", "auto", "dual", "ipv6_first", "ipv4", "ipv6"} {
		cfg := Default()
		cfg.Proxy.IPVersion = v
		if err := cfg.Validate(); err != nil {
			t.Errorf("%q refused: %v", v, err)
		}
	}
}
