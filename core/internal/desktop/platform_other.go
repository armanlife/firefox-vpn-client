//go:build !windows

package desktop

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"

	"github.com/armanlife/firefox-vpn-client/core/internal/securefile"
	"github.com/armanlife/firefox-vpn-client/core/internal/service"
)

const trayFromConsoleSupported = false

func enableTerminalColors() bool {
	return os.Getenv("TERM") != "dumb"
}

func startDetachedTray(service.DataPaths) error {
	return errors.New("not supported on this platform")
}

func trayRunning(service.DataPaths) bool { return false }

func StartedWithOwnConsole() bool { return false }

func DetachConsole() {}

// acquireSingleInstance makes sure only one desktop host (the tray icon or
// the app mode) runs per data folder, with an advisory lock that the kernel
// releases when the process exits.
func acquireSingleInstance(paths service.DataPaths) (release func(), ok bool) {
	f, err := os.OpenFile(filepath.Join(paths.Dir, ".tray.lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return func() {}, true
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = f.Close()
		return func() {}, false
	}
	return func() { _ = f.Close() }, true
}

// autostartDir is the XDG autostart folder; tests replace it.
var autostartDir = func() (string, error) {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		base = filepath.Join(home, ".config")
	}
	return filepath.Join(base, "autostart"), nil
}

const autostartFile = "firefox-vpn.desktop"

func autostartEnabled(service.DataPaths) bool {
	dir, err := autostartDir()
	if err != nil {
		return false
	}
	_, err = os.Stat(filepath.Join(dir, autostartFile))
	return err == nil
}

// SetAutostart adds or removes the tray from the desktop session's
// autostart entries.
func SetAutostart(paths service.DataPaths, enabled bool) error {
	dir, err := autostartDir()
	if err != nil {
		return err
	}
	path := filepath.Join(dir, autostartFile)
	if !enabled {
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		return nil
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	entry := fmt.Sprintf("[Desktop Entry]\nType=Application\nName=Firefox VPN\nComment=Firefox VPN proxy tray icon\nExec=%s -tray -data-dir %s\nTerminal=false\nX-GNOME-Autostart-enabled=true\n",
		desktopQuote(exe), desktopQuote(paths.Dir))
	return securefile.WritePrivate(path, []byte(entry))
}

// desktopQuote quotes an Exec argument per the Desktop Entry specification.
func desktopQuote(arg string) string {
	r := strings.NewReplacer(`\`, `\\\\`, `"`, `\\"`, "`", "\\\\`", "$", `\\$`, "%", "%%")
	return `"` + r.Replace(arg) + `"`
}

// notify shows a desktop notification when notify-send is available.
func notify(title, body string) {
	path, err := exec.LookPath("notify-send")
	if err != nil {
		return
	}
	cmd := exec.Command(path, "--app-name=Firefox VPN", "--", title, body)
	if err := cmd.Start(); err != nil {
		return
	}
	go func() { _ = cmd.Wait() }()
}

// browserAvailable reports whether openBrowser can show a page here: on
// macOS, or on a Linux desktop (a display and xdg-open). A server has
// neither; the console then gives the dashboard's address instead.
func browserAvailable() bool {
	if runtime.GOOS == "darwin" {
		return true
	}
	if os.Getenv("DISPLAY") == "" && os.Getenv("WAYLAND_DISPLAY") == "" {
		return false
	}
	_, err := exec.LookPath("xdg-open")
	return err == nil
}

// openBrowser opens url in the default browser.
func openBrowser(url string) error {
	opener := "xdg-open"
	if runtime.GOOS == "darwin" {
		opener = "open"
	}
	cmd := exec.Command(opener, url)
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() { _ = cmd.Wait() }()
	return nil
}

// registerNotificationApp has nothing to register: notify-send names the
// program itself.
func registerNotificationApp(service.DataPaths) {}
