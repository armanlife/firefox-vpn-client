package update

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/sys/windows/registry"
)

// A copy that a version before 1.0.9 installed: Setup's entry takes the
// new name and icon, and the package's empty file for the old core goes;
// another folder's entry, and a real file, stay. The test uses a key of
// its own, never the app's.
func TestMigrateRenamesSetupsEntryAndRemovesThePlaceholder(t *testing.T) {
	random := make([]byte, 6)
	rand.Read(random)
	old := uninstallKey
	uninstallKey = `Software\ArmanVPNUpdateTest-` + hex.EncodeToString(random)
	t.Cleanup(func() {
		registry.DeleteKey(registry.CURRENT_USER, uninstallKey)
		uninstallKey = old
	})
	app := t.TempDir()
	os.MkdirAll(filepath.Join(app, "core"), 0o755)
	placeholder := filepath.Join(app, legacyCore)
	os.WriteFile(placeholder, nil, 0o644)
	// No entry: a portable copy.
	if err := Migrate(app); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(placeholder); !os.IsNotExist(err) {
		t.Fatalf("the placeholder is still there: %v", err)
	}
	k, _, err := registry.CreateKey(registry.CURRENT_USER, uninstallKey, registry.ALL_ACCESS)
	if err != nil {
		t.Fatal(err)
	}
	defer k.Close()
	value := func(name string) string {
		v, _, _ := k.GetStringValue(name)
		return v
	}
	k.SetStringValue("InstallLocation", `C:\Elsewhere\`)
	k.SetStringValue("DisplayName", "Firefox VPN")
	k.SetStringValue("DisplayIcon", `C:\Elsewhere\firefox-vpn.exe`)
	if err := Migrate(app); err != nil || value("DisplayName") != "Firefox VPN" {
		t.Fatalf("another folder's entry changed: %v, %q", err, value("DisplayName"))
	}
	k.SetStringValue("InstallLocation", app+`\`)
	k.SetStringValue("DisplayIcon", filepath.Join(app, "firefox-vpn.exe"))
	// A file the user put there under that name is not the placeholder.
	os.WriteFile(placeholder, []byte("MZ"), 0o644)
	if err := Migrate(app); err != nil {
		t.Fatal(err)
	}
	if value("DisplayName") != "Arman VPN" || value("DisplayIcon") != filepath.Join(app, "arman-vpn.exe") {
		t.Fatalf("entry: %q, %q", value("DisplayName"), value("DisplayIcon"))
	}
	if _, err := os.Stat(placeholder); err != nil {
		t.Fatalf("a real file went: %v", err)
	}
	// Once more: nothing changes.
	if err := Migrate(app); err != nil || value("DisplayName") != "Arman VPN" {
		t.Fatalf("again: %v, %q", err, value("DisplayName"))
	}
}
