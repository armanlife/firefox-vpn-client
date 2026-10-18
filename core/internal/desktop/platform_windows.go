//go:build windows

package desktop

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"

	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/service"
	"github.com/armanlife/firefox-vpn-client/core/internal/winsvc"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

var (
	kernel32                  = windows.NewLazySystemDLL("kernel32.dll")
	procGetConsoleProcessList = kernel32.NewProc("GetConsoleProcessList")
	procFreeConsole           = kernel32.NewProc("FreeConsole")
)

// StartedWithOwnConsole reports whether this process is alone on its
// console, which is the case when it was started from Explorer rather than
// from a terminal.
func StartedWithOwnConsole() bool {
	var pids [4]uint32
	n, _, _ := procGetConsoleProcessList.Call(uintptr(unsafe.Pointer(&pids[0])), uintptr(len(pids)))
	return n == 1
}

// DetachConsole closes the console window of a process started from
// Explorer; the tray icon replaces it.
func DetachConsole() {
	_, _, _ = procFreeConsole.Call()
}

// acquireSingleInstance makes sure only one desktop host (the tray icon or
// the app mode) runs per data folder. The returned release function is a
// no-op when another instance owns it.
func acquireSingleInstance(paths service.DataPaths) (release func(), ok bool) {
	name := trayMutexName(paths)
	h, err := windows.CreateMutex(nil, false, name)
	if errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		if h != 0 {
			_ = windows.CloseHandle(h)
		}
		return func() {}, false
	}
	if err != nil {
		// Without a mutex, prefer running over refusing to start.
		return func() {}, true
	}
	return func() { _ = windows.CloseHandle(h) }, true
}

func trayMutexName(paths service.DataPaths) *uint16 {
	sum := sha256.Sum256([]byte(strings.ToLower(paths.Dir)))
	name, _ := windows.UTF16PtrFromString(`Local\FirefoxVPN-tray-` + hex.EncodeToString(sum[:8]))
	return name
}

// trayRunning reports whether a tray icon runs for the data folder.
func trayRunning(paths service.DataPaths) bool {
	h, err := windows.OpenMutex(windows.SYNCHRONIZE, false, trayMutexName(paths))
	if err != nil {
		return false
	}
	_ = windows.CloseHandle(h)
	return true
}

// autostartKey is the per-user Run key; tests replace it.
var autostartKey = `Software\Microsoft\Windows\CurrentVersion\Run`

const autostartValue = "FirefoxVPN"

func autostartCommand(paths service.DataPaths) (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	return winsvc.CommandLine(exe, []string{"-tray", "-data-dir", paths.Dir}), nil
}

// autostartEnabled reports whether the tray starts at sign-in.
func autostartEnabled(paths service.DataPaths) bool {
	k, err := registry.OpenKey(registry.CURRENT_USER, autostartKey, registry.QUERY_VALUE)
	if err != nil {
		return false
	}
	defer k.Close()
	value, _, err := k.GetStringValue(autostartValue)
	return err == nil && value != ""
}

// SetAutostart adds or removes the tray from the user's sign-in programs.
func SetAutostart(paths service.DataPaths, enabled bool) error {
	k, _, err := registry.CreateKey(registry.CURRENT_USER, autostartKey, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if !enabled {
		if err := k.DeleteValue(autostartValue); err != nil && !errors.Is(err, registry.ErrNotExist) {
			return err
		}
		return nil
	}
	command, err := autostartCommand(paths)
	if err != nil {
		return err
	}
	return k.SetStringValue(autostartValue, command)
}

// notificationAppID names the program's notifications. Windows shows a
// notification under the app ID that sends it; registerNotificationApp
// gives this one the program's name and icon. Before, the notifications
// used PowerShell's app ID (PowerShell only delivers them) and showed as
// "Windows PowerShell".
const notificationAppID = "FirefoxVPN.Proxy"

// notificationAppKey is the app ID's registration for the user; tests
// replace it.
var notificationAppKey = `Software\Classes\AppUserModelId\` + notificationAppID

// notificationIconFile is the notifications' icon in the data folder
// (Windows reads it from a file).
const notificationIconFile = "notification-icon.png"

// registerNotificationApp registers the notification app ID with the
// program's name and icon. Every tray start repeats it, so a moved data
// folder updates the icon path.
func registerNotificationApp(paths service.DataPaths) {
	k, _, err := registry.CreateKey(registry.CURRENT_USER, notificationAppKey, registry.SET_VALUE)
	if err != nil {
		logx.Debug("registering the notification name failed err=%s", logx.Err(err))
		return
	}
	defer k.Close()
	if err := k.SetStringValue("DisplayName", "Firefox VPN"); err != nil {
		logx.Debug("registering the notification name failed err=%s", logx.Err(err))
		return
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, AppIcon(128)); err != nil {
		return
	}
	icon := filepath.Join(paths.Dir, notificationIconFile)
	if err := os.WriteFile(icon, buf.Bytes(), 0o644); err != nil {
		// The notifications keep the name, without the icon.
		logx.Debug("writing the notification icon failed err=%s", logx.Err(err))
		return
	}
	_ = k.SetStringValue("IconUri", icon)
}

// toastScript shows a Windows notification under the app ID in FVPN_APP;
// the text comes from environment variables so it is never parsed as
// script.
const toastScript = `$ErrorActionPreference='Stop'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
$t = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$x = $t.GetElementsByTagName('text')
$x.Item(0).AppendChild($t.CreateTextNode($env:FVPN_TITLE)) | Out-Null
$x.Item(1).AppendChild($t.CreateTextNode($env:FVPN_BODY)) | Out-Null
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($env:FVPN_APP).Show([Windows.UI.Notifications.ToastNotification]::new($t))`

// notify shows a desktop notification, best effort.
func notify(title, body string) {
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", toastScript)
	cmd.Env = append(os.Environ(), "FVPN_APP="+notificationAppID, "FVPN_TITLE="+title, "FVPN_BODY="+body)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: windows.CREATE_NO_WINDOW}
	if err := cmd.Start(); err != nil {
		logx.Debug("notification failed err=%s", logx.Err(err))
		return
	}
	go func() { _ = cmd.Wait() }()
}

// openBrowser opens url in the default browser.
// browserAvailable reports whether openBrowser can show a page: always on
// Windows.
func browserAvailable() bool { return true }

func openBrowser(url string) error {
	verb, _ := windows.UTF16PtrFromString("open")
	target, err := windows.UTF16PtrFromString(url)
	if err != nil {
		return err
	}
	return windows.ShellExecute(0, verb, target, nil, nil, windows.SW_SHOWNORMAL)
}

// trayFromConsoleSupported: the console never starts a tray copy of the
// proxy. It controls the one that serves the data folder (the desktop
// app's core, the Windows service, or a tray started with -tray) or runs
// the proxy in its own window, as on Linux; a second copy would only
// fight the app over its ports.
const trayFromConsoleSupported = false

// enableTerminalColors turns on ANSI escape processing for the console
// (Windows 10 1511 and later) and sets the window title.
func enableTerminalColors() bool {
	h := windows.Handle(os.Stdout.Fd())
	var mode uint32
	if err := windows.GetConsoleMode(h, &mode); err != nil {
		return false
	}
	if err := windows.SetConsoleMode(h, mode|windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING|windows.ENABLE_PROCESSED_OUTPUT); err != nil {
		return false
	}
	os.Stdout.WriteString("\x1b]0;Firefox VPN\x07")
	return true
}

// startDetachedTray starts the tray icon as a separate process without a
// console window.
func startDetachedTray(paths service.DataPaths) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	cmd := exec.Command(exe, "-tray", "-data-dir", paths.Dir)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: windows.DETACHED_PROCESS | windows.CREATE_NEW_PROCESS_GROUP,
		HideWindow:    true,
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	return cmd.Process.Release()
}
