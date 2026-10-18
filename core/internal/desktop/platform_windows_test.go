//go:build windows

package desktop

import (
	"bytes"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/armanlife/firefox-vpn-client/core/internal/service"
	"github.com/armanlife/firefox-vpn-client/core/internal/winsvc"

	"golang.org/x/sys/windows/registry"
)

func TestAutostartWritesRunValue(t *testing.T) {
	key := `Software\FirefoxVPNTest-` + strings.ReplaceAll(t.Name(), "/", "-")
	old := autostartKey
	autostartKey = key
	t.Cleanup(func() {
		autostartKey = old
		_ = registry.DeleteKey(registry.CURRENT_USER, key)
	})
	paths := service.DataPaths{Dir: filepath.Join(t.TempDir(), "my data")}

	if autostartEnabled(paths) {
		t.Fatal("enabled before setting")
	}
	if err := SetAutostart(paths, true); err != nil {
		t.Fatal(err)
	}
	k, err := registry.OpenKey(registry.CURRENT_USER, key, registry.QUERY_VALUE)
	if err != nil {
		t.Fatal(err)
	}
	value, _, err := k.GetStringValue(autostartValue)
	k.Close()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(value, `"`) || !strings.Contains(value, ` -tray -data-dir "`+paths.Dir+`"`) {
		t.Fatalf("unexpected Run value %q", value)
	}
	if !autostartEnabled(paths) {
		t.Fatal("not reported as enabled")
	}
	if err := SetAutostart(paths, false); err != nil {
		t.Fatal(err)
	}
	if err := SetAutostart(paths, false); err != nil {
		t.Fatalf("removing twice: %v", err)
	}
	if autostartEnabled(paths) {
		t.Fatal("still enabled after removal")
	}
}

func TestQueryServiceWithoutAdministratorRights(t *testing.T) {
	st, err := winsvc.Query()
	if err != nil {
		t.Fatalf("querying the service manager: %v", err)
	}
	t.Logf("FirefoxVPN service: %s exe=%q data=%q", st, st.ExePath, st.DataDir)
}

func TestParseServiceCommandLine(t *testing.T) {
	for in, want := range map[string][2]string{
		`"C:\Program Files\Firefox VPN\firefox-vpn-core.exe" -service -data-dir "C:\x y\data"`: {`C:\Program Files\Firefox VPN\firefox-vpn-core.exe`, `C:\x y\data`},
		`D:\Tools\firefox-vpn-core.exe -service -data-dir D:\Tools\data`:                       {`D:\Tools\firefox-vpn-core.exe`, `D:\Tools\data`},
		`C:\Tools\vpn.exe -service`: {`C:\Tools\vpn.exe`, ""},
	} {
		exe, dir := winsvc.ParseCommandLine(in)
		if exe != want[0] || dir != want[1] {
			t.Errorf("parseServiceCommandLine(%q) = %q, %q; want %q, %q", in, exe, dir, want[0], want[1])
		}
	}
}

func TestRegisterNotificationApp(t *testing.T) {
	key := `Software\FirefoxVPNTest-` + t.Name()
	old := notificationAppKey
	notificationAppKey = key
	t.Cleanup(func() {
		notificationAppKey = old
		_ = registry.DeleteKey(registry.CURRENT_USER, key)
	})
	paths := service.DataPaths{Dir: t.TempDir()}

	registerNotificationApp(paths)
	k, err := registry.OpenKey(registry.CURRENT_USER, key, registry.QUERY_VALUE)
	if err != nil {
		t.Fatal(err)
	}
	defer k.Close()
	name, _, err := k.GetStringValue("DisplayName")
	if err != nil || name != "Firefox VPN" {
		t.Fatalf("DisplayName %q: %v", name, err)
	}
	icon, _, err := k.GetStringValue("IconUri")
	if err != nil || icon != filepath.Join(paths.Dir, notificationIconFile) {
		t.Fatalf("IconUri %q: %v", icon, err)
	}
	data, err := os.ReadFile(icon)
	if err != nil {
		t.Fatal(err)
	}
	if img, err := png.Decode(bytes.NewReader(data)); err != nil || img.Bounds().Dx() != 128 {
		t.Fatalf("icon file: %v", err)
	}
}
