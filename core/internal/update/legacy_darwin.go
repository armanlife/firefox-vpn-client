package update

import (
	"os"
	"path/filepath"

	"github.com/armanlife/arman-vpn-client/core/internal/logx"
)

// The macOS tar.gz's bundle holds links under the old names in
// Contents/MacOS (Firefox VPN, firefox-vpn-core), which stay: the bundle is
// sealed by its signature.
func init() { relocate = renameBundle }

// renameBundle moves a bundle of a version before 1.0.9 (Firefox VPN.app)
// to Arman VPN.app beside it, once an update replaced its contents and
// while nothing of the app runs; it stays where it is when that name is
// taken or the move fails.
func renameBundle(appDir string) string {
	if filepath.Base(appDir) != oldAppName+".app" {
		return appDir
	}
	target := filepath.Join(filepath.Dir(appDir), appName+".app")
	if _, err := os.Lstat(target); err == nil {
		return appDir
	}
	if err := os.Rename(appDir, target); err != nil {
		logx.Warn("update: renaming the app failed app=%s err=%s", appDir, logx.Err(err))
		return appDir
	}
	logx.Info("update: renamed the app from=%s to=%s", appDir, target)
	return target
}

// Migrate: the bundle gets its new name at the next update (renameBundle),
// when the app does not run.
func Migrate(string) error { return nil }
