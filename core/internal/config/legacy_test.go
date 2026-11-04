package config

import (
	"os"
	"path/filepath"
	"testing"
)

// The app's data folder of a version before 1.0.9 moves to the new name,
// with its files, once: not over a new folder, and not for other folders.
func TestTheOldDataFolderMovesToTheNewName(t *testing.T) {
	for _, names := range [][2]string{{"Firefox VPN Client", "Arman VPN"}, {"firefox-vpn-client", "arman-vpn"}} {
		base := t.TempDir()
		old, dir := filepath.Join(base, names[0]), filepath.Join(base, names[1])
		os.MkdirAll(filepath.Join(old, "accounts"), 0o700)
		os.WriteFile(filepath.Join(old, "config.json"), []byte("{}"), 0o600)
		MoveLegacyDataDir(dir)
		if _, err := os.Stat(filepath.Join(dir, "config.json")); err != nil {
			t.Fatalf("%s: not moved: %v", names[0], err)
		}
		if _, err := os.Stat(old); !os.IsNotExist(err) {
			t.Fatalf("%s: still there: %v", names[0], err)
		}
		// A new folder exists: the old one stays apart.
		os.MkdirAll(old, 0o700)
		MoveLegacyDataDir(dir)
		if _, err := os.Stat(old); err != nil {
			t.Fatalf("%s: moved over the new folder: %v", names[0], err)
		}
	}
	// user-data beside the app keeps its name.
	base := t.TempDir()
	os.MkdirAll(filepath.Join(base, "Firefox VPN Client"), 0o700)
	MoveLegacyDataDir(filepath.Join(base, DataDirName))
	if _, err := os.Stat(filepath.Join(base, DataDirName)); !os.IsNotExist(err) {
		t.Fatalf("user-data was made: %v", err)
	}
}
