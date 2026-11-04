package update

import (
	"os"
	"path/filepath"
	"strings"
)

// The links under the old names in the Linux tar.gz.
const (
	legacyApp  = "firefox-vpn"
	legacyCore = "core/firefox-vpn-core"
)

// desktopFile is the applications menu's entry that install.sh writes
// (com.arman.firefoxvpn.desktop in the user's data folder); tests set it.
var desktopFile = func() string {
	base := os.Getenv("XDG_DATA_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return ""
		}
		base = filepath.Join(home, ".local", "share")
	}
	return filepath.Join(base, "applications", "com.arman.firefoxvpn.desktop")
}

// Migrate puts a copy of the app that a version before 1.0.9 installed in
// appDir on the new name: the applications menu's entry starts the app by
// its new name, and the links the package carries under the old names go.
func Migrate(appDir string) error {
	oldExe := filepath.Join(appDir, legacyApp)
	newExe := filepath.Join(appDir, linuxPackage.app)
	if file := desktopFile(); file != "" {
		if data, err := os.ReadFile(file); err == nil {
			text := strings.ReplaceAll(string(data), `"`+oldExe+`"`, `"`+newExe+`"`)
			text = strings.ReplaceAll(text, "Name="+oldAppName+"\n", "Name="+appName+"\n")
			if text != string(data) {
				if err := os.WriteFile(file, []byte(text), 0o644); err != nil {
					return err
				}
			}
		}
	}
	for _, link := range []string{oldExe, filepath.Join(appDir, filepath.FromSlash(legacyCore))} {
		if info, err := os.Lstat(link); err == nil && info.Mode()&os.ModeSymlink != 0 {
			_ = os.Remove(link)
		}
	}
	return nil
}
