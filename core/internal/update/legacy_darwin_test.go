package update

import (
	"os"
	"path/filepath"
	"testing"
)

// After an update, the bundle of a version before 1.0.9 takes the new
// name; one of another name, or one whose new name is taken, stays.
func TestTheOldBundleIsRenamedAfterAnUpdate(t *testing.T) {
	dir := t.TempDir()
	old := filepath.Join(dir, "Firefox VPN.app")
	os.MkdirAll(filepath.Join(old, "Contents"), 0o755)
	if got := renameBundle(old); got != filepath.Join(dir, "Arman VPN.app") {
		t.Fatalf("renamed to %s", got)
	}
	if _, err := os.Stat(filepath.Join(dir, "Arman VPN.app", "Contents")); err != nil {
		t.Fatal(err)
	}
	other := filepath.Join(dir, "Mine.app")
	os.MkdirAll(other, 0o755)
	if got := renameBundle(other); got != other {
		t.Fatalf("another bundle went to %s", got)
	}
	os.MkdirAll(old, 0o755)
	if got := renameBundle(old); got != old {
		t.Fatalf("the taken name: %s", got)
	}
}
