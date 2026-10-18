//go:build !windows

package desktop

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/armanlife/firefox-vpn-client/core/internal/service"
)

func TestAutostartWritesDesktopEntry(t *testing.T) {
	dir := t.TempDir()
	old := autostartDir
	autostartDir = func() (string, error) { return dir, nil }
	t.Cleanup(func() { autostartDir = old })
	paths := service.DataPaths{Dir: "/opt/firefox vpn/data"}

	if err := SetAutostart(paths, true); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, autostartFile))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `-tray -data-dir "/opt/firefox vpn/data"`) {
		t.Fatalf("unexpected desktop entry:\n%s", data)
	}
	if !autostartEnabled(paths) {
		t.Fatal("not reported as enabled")
	}
	if err := SetAutostart(paths, false); err != nil {
		t.Fatal(err)
	}
	if autostartEnabled(paths) {
		t.Fatal("still enabled after removal")
	}
}

func TestDesktopQuote(t *testing.T) {
	if got := desktopQuote(`/a b/$x"%`); got != `"/a b/\\$x\\"%%"` {
		t.Fatalf("desktopQuote = %s", got)
	}
}
