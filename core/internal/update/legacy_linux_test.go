package update

import (
	"os"
	"path/filepath"
	"testing"
)

// A copy that a version before 1.0.9 installed: the menu's entry starts the
// app by its new name, and the package's links under the old names go; a
// real file under an old name stays.
func TestMigrateFixesTheMenuEntryAndRemovesTheLinks(t *testing.T) {
	app := t.TempDir()
	os.MkdirAll(filepath.Join(app, "core"), 0o755)
	os.WriteFile(filepath.Join(app, "arman-vpn"), []byte("app"), 0o755)
	os.Symlink("arman-vpn", filepath.Join(app, "firefox-vpn"))
	os.Symlink("arman-vpn-core", filepath.Join(app, "core", "firefox-vpn-core"))
	entry := filepath.Join(t.TempDir(), "com.arman.firefoxvpn.desktop")
	old := desktopFile
	desktopFile = func() string { return entry }
	t.Cleanup(func() { desktopFile = old })
	os.WriteFile(entry, []byte("[Desktop Entry]\nName=Firefox VPN\nExec=\""+filepath.Join(app, "firefox-vpn")+"\"\nIcon="+app+"/data/app_icon.png\n"), 0o644)

	if err := Migrate(app); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(entry)
	want := "[Desktop Entry]\nName=Arman VPN\nExec=\"" + filepath.Join(app, "arman-vpn") + "\"\nIcon=" + app + "/data/app_icon.png\n"
	if string(data) != want {
		t.Fatalf("entry:\n%s\nwant:\n%s", data, want)
	}
	for _, link := range []string{"firefox-vpn", "core/firefox-vpn-core"} {
		if _, err := os.Lstat(filepath.Join(app, link)); !os.IsNotExist(err) {
			t.Fatalf("%s is still there: %v", link, err)
		}
	}
	// A real file is not the package's link.
	os.WriteFile(filepath.Join(app, "firefox-vpn"), []byte("mine"), 0o755)
	if err := Migrate(app); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(app, "firefox-vpn")); err != nil {
		t.Fatalf("a real file went: %v", err)
	}
}
