package update

import (
	"errors"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/windows/registry"
)

// The entries under the old names in the Windows zip: a copy of the app
// (the app starts the one under the new name instead, and then removes
// it: app/windows/runner/main.cpp) and an empty file for the core.
const (
	legacyApp  = "firefox-vpn.exe"
	legacyCore = `core\firefox-vpn-core.exe`
)

// Migrate puts a copy of the app that a version before 1.0.9 installed in
// appDir on the new name: Setup's entry in Windows' list of installed apps
// gets the new name and icon (the app's own update swaps files only, so
// the entry keeps what the old Setup wrote), and the empty file the
// package carries for the old core goes. The shortcuts and the autostart
// entry are the app's (app/windows/runner).
func Migrate(appDir string) error {
	core := filepath.Join(appDir, legacyCore)
	if info, err := os.Stat(core); err == nil && info.Mode().IsRegular() && info.Size() == 0 {
		_ = os.Remove(core)
	}
	k, err := registry.OpenKey(registry.CURRENT_USER, uninstallKey, registry.QUERY_VALUE|registry.SET_VALUE)
	if errors.Is(err, registry.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	defer k.Close()
	location, _, err := k.GetStringValue("InstallLocation")
	if err != nil || !strings.EqualFold(filepath.Clean(location), filepath.Clean(appDir)) {
		return nil
	}
	if name, _, err := k.GetStringValue("DisplayName"); err == nil && strings.HasPrefix(name, oldAppName) {
		if err := k.SetStringValue("DisplayName", appName+strings.TrimPrefix(name, oldAppName)); err != nil {
			return err
		}
	}
	if icon, _, err := k.GetStringValue("DisplayIcon"); err == nil && strings.EqualFold(filepath.Clean(icon), filepath.Join(filepath.Clean(appDir), legacyApp)) {
		if err := k.SetStringValue("DisplayIcon", filepath.Join(filepath.Clean(appDir), windowsPackage.app)); err != nil {
			return err
		}
	}
	return nil
}
