package update

// Up to 1.0.8 the program was called Firefox VPN, and its files and
// folders had that name (firefox-vpn.exe, core/firefox-vpn-core.exe, the
// macOS bundle Firefox VPN.app). The update of those versions checks that
// a new version's package holds the app and its core under these names,
// and starts the app by its name once the files are swapped; so each
// package also carries an entry under the old names (legacyApp and
// legacyCore of each system: on Windows a copy of the app and an empty
// file, on Linux and macOS links), which Migrate removes again where it
// can. The packages may stop carrying them once no version before 1.0.9 is
// in use.

// The app's name since 1.0.9, and the one before.
const (
	appName    = "Arman VPN"
	oldAppName = "Firefox VPN"
)

// relocate gives the app in appDir its new name after an update installed
// it, and returns where it is then; on macOS the bundle of a version before
// 1.0.9 becomes Arman VPN.app (legacy_darwin.go), elsewhere the folder
// stays (one the user chose, or Setup's).
var relocate = func(appDir string) string { return appDir }
