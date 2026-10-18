//go:build windows || linux

package desktop

import (
	"context"
	"sync"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/service"
	"github.com/armanlife/firefox-vpn-client/core/internal/version"
	"github.com/armanlife/firefox-vpn-client/core/internal/winsvc"

	"fyne.io/systray"
)

const trayPollInterval = 3 * time.Second

// trayApp is the notification-area icon. Its color and tooltip show the
// service state; its menu is kept short on purpose (dashboard, restart,
// exit). Start at sign-in comes with the Windows service. Status details, accounts, and the Windows
// service live in the dashboard and the terminal status screen. When no service is reachable it runs the
// service in its own process; when the Windows service (or another copy)
// already serves the data folder, it only talks to it through the local API.
type trayApp struct {
	paths   service.DataPaths
	verbose bool
	client  *service.Client

	mu  sync.Mutex
	own *service.Daemon // in-process service; nil when another process serves

	// Last observed state, for notifications on changes.
	seen        bool
	lastPhase   string
	lastMessage string
	lastAccount string
	lastReauth  int

	failures     int       // consecutive failed polls
	lastOwnStart time.Time // last attempt to run the service in-process
	sysproxy     systemProxySync
	// folderRequest is the last open-folder count seen in the status.
	folderRequest     uint64
	folderRequestSeen bool

	mOpen, mRestart, mQuit *systray.MenuItem
	// mModes are the system proxy modes, one checked (Windows).
	mModes                             map[string]*systray.MenuItem
	iconOK, iconWait, iconErr, iconOff []byte
	iconSet                            []byte
	// Faded running icons while the proxy sleeps (proxy.idle_sleep).
	iconOKAsleep, iconSetAsleep []byte
}

// RunTray shows the tray icon until the user quits.
func RunTray(paths service.DataPaths, verbose bool) error {
	release, ok := acquireSingleInstance(paths)
	if !ok {
		// A tray already runs for this data folder (two windows opened at
		// once, or sign-in start plus a double-click); this copy leaves.
		logx.Debug("tray: another tray serves this data folder; exiting")
		return nil
	}
	defer release()
	registerNotificationApp(paths)
	app := &trayApp{paths: paths, verbose: verbose, client: service.NewClient(paths)}
	app.iconOK = trayIcon(iconRunning)
	app.iconWait = trayIcon(iconWaiting)
	app.iconErr = trayIcon(iconError)
	app.iconOff = trayIcon(iconOff)
	app.iconSet = trayIcon(iconSet)
	app.iconOKAsleep = trayIcon(iconRunningAsleep)
	app.iconSetAsleep = trayIcon(iconSetAsleep)
	systray.Run(app.onReady, app.onExit)
	return nil
}

func (a *trayApp) onReady() {
	systray.SetIcon(a.iconOff)
	systray.SetTitle("Firefox VPN")
	systray.SetTooltip("Firefox VPN")

	// The layout follows v2rayN's tray menu.
	a.mOpen = systray.AddMenuItem("Open dashboard", "Open the web dashboard")
	if systemProxySupported {
		systray.AddSeparator()
		a.mModes = map[string]*systray.MenuItem{}
		for _, m := range systemProxyModes {
			a.mModes[m.mode] = systray.AddMenuItemCheckbox(m.label, m.tip, false)
		}
	}
	systray.AddSeparator()
	a.mRestart = systray.AddMenuItem("Restart proxy", "Restart the proxy engine")
	systray.AddSeparator()
	a.mQuit = systray.AddMenuItem("Quit", "")
	systray.SetOnTapped(a.openDashboard)

	go a.handleClicks()
	go a.start()
}

func (a *trayApp) onExit() {
	a.sysproxy.clear()
	a.stopOwn()
}

// start decides whether to run the service in this process, then keeps the
// menu current.
func (a *trayApp) start() {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	_, err := a.client.Status(ctx)
	cancel()
	if err != nil {
		if st, qerr := winsvc.QueryFor(a.paths); qerr == nil && st.Installed {
			logx.Info("tray: waiting for the background service state=%s", st)
		} else {
			a.startOwn()
		}
	} else {
		logx.Info("tray: using the running service")
	}
	a.refresh()
	ticker := time.NewTicker(trayPollInterval)
	defer ticker.Stop()
	for range ticker.C {
		a.refresh()
	}
}

func (a *trayApp) startOwn() {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.own != nil {
		return
	}
	a.lastOwnStart = time.Now()
	// The status screen's "exit completely" ends this process.
	d, err := newHostedDaemon(a.paths, a.verbose, systray.Quit)
	if err != nil {
		logx.Error("tray: starting the service failed err=%s", logx.Err(err))
		notify("Firefox VPN could not start", err.Error())
		return
	}
	a.own = d
	go func() {
		if err := d.Run(); err != nil {
			logx.Error("tray: the service stopped err=%s", logx.Err(err))
			notify("Firefox VPN stopped", err.Error())
		}
		a.mu.Lock()
		if a.own == d {
			a.own = nil
		}
		a.mu.Unlock()
	}()
}

func (a *trayApp) stopOwn() {
	a.mu.Lock()
	d := a.own
	a.own = nil
	a.mu.Unlock()
	if d != nil {
		d.Shutdown()
	}
}

func (a *trayApp) ownsService() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.own != nil
}

// refresh polls the service and updates the icon, menu, and notifications.
func (a *trayApp) refresh() {
	st, err := pollStatus(a.client)
	svcState, _ := winsvc.QueryFor(a.paths)
	if a.ownsService() {
		a.mQuit.SetTitle("Exit Firefox VPN (stops the proxy)")
	} else {
		a.mQuit.SetTitle("Close icon (the service keeps running)")
	}
	if err != nil {
		// Take over when the copy we were talking to has gone away.
		a.failures++
		if a.failures >= 2 && !svcState.Installed && !a.ownsService() && time.Since(a.lastOwnStart) > time.Minute {
			a.startOwn()
		}
		systray.SetIcon(a.iconOff)
		text := "Service not reachable"
		switch {
		case svcState.Installed && !svcState.Running():
			text = "Background service " + svcState.String()
		case svcState.Running() || a.ownsService():
			text = "Starting…"
		}
		systray.SetTooltip("Firefox VPN: " + text)
		a.mRestart.Disable()
		a.sysproxy.update(nil)
		return
	}
	a.failures = 0
	// A newer copy of the program serves the data folder (after an
	// update); leave the icon to it.
	if !a.ownsService() && st.Version != "" && version.Newer(st.Version, version.Current) {
		logx.Info("tray: version %s serves the data folder; closing this %s icon", st.Version, version.Current)
		systray.Quit()
		return
	}
	a.mRestart.Enable()
	a.sysproxy.update(&st)
	// The Windows service cannot open a window on this desktop; the
	// dashboard's "Open folder" asks the tray through the status.
	if a.folderRequestSeen && st.OpenFolderRequest > a.folderRequest {
		if err := openBrowser(a.paths.Dir); err != nil {
			notify("Cannot open the folder", err.Error())
		}
	}
	a.folderRequest, a.folderRequestSeen = st.OpenFolderRequest, true
	for mode, item := range a.mModes {
		if mode == st.SystemProxy {
			item.Check()
		} else {
			item.Uncheck()
		}
	}
	active := a.sysproxy.active()
	systray.SetTooltip("Firefox VPN: " + st.Summary())
	switch st.State.Phase {
	case "running":
		asleep := st.Proxy != nil && !st.Proxy.SleepingSince.IsZero()
		switch {
		case active && asleep:
			systray.SetIcon(a.iconSetAsleep)
		case active:
			systray.SetIcon(a.iconSet)
		case asleep:
			systray.SetIcon(a.iconOKAsleep)
		default:
			systray.SetIcon(a.iconOK)
		}
	case "error":
		systray.SetIcon(a.iconErr)
	default:
		systray.SetIcon(a.iconWait)
	}
	a.notifyChanges(st)
}

// notifyChanges shows notifications for account switches, errors, and
// accounts that need signing in again.
func (a *trayApp) notifyChanges(st service.TrayStatus) {
	account := ""
	if st.ActiveAccount != nil {
		account = st.ActiveAccount.ID
	}
	reauth := st.Accounts["reauth_required"]
	if a.seen {
		if account != "" && a.lastAccount != "" && account != a.lastAccount {
			name := st.ActiveAccount.Name
			if name == "" {
				name = st.ActiveAccount.Email
			}
			notify("Switched account", "Now using "+name+".")
		}
		if st.State.Phase != a.lastPhase || st.State.Message != a.lastMessage {
			switch st.State.Phase {
			case "error":
				notify("Firefox VPN error", st.State.Message)
			case "waiting":
				// Waiting for Wi-Fi or a cable is expected, not news.
				if st.State.Message != service.MessageWaitingForNetwork {
					notify("Firefox VPN is waiting", st.State.Message)
				}
			case "running":
				if a.lastPhase == "error" || a.lastPhase == "waiting" {
					notify("Firefox VPN connected", "The proxy is running again.")
				}
			}
		}
		if reauth > a.lastReauth {
			notify("Sign-in needed", "An account must be signed in again in the dashboard.")
		}
	}
	a.seen = true
	a.lastPhase, a.lastMessage, a.lastAccount, a.lastReauth = st.State.Phase, st.State.Message, account, reauth
}

func (a *trayApp) handleClicks() {
	// A mode item's clicks are forwarded with its mode.
	modeClicks := make(chan string)
	for mode, item := range a.mModes {
		go func(mode string, clicks <-chan struct{}) {
			for range clicks {
				modeClicks <- mode
			}
		}(mode, item.ClickedCh)
	}
	for {
		select {
		case mode := <-modeClicks:
			go a.setSystemProxyMode(mode)
		case <-a.mOpen.ClickedCh:
			a.openDashboard()
		case <-a.mRestart.ClickedCh:
			go a.restartProxy()
		case <-a.mQuit.ClickedCh:
			systray.Quit()
			return
		}
	}
}

func (a *trayApp) openDashboard() {
	url, err := a.client.DashboardURL()
	if err == nil {
		err = openBrowser(url)
	}
	if err != nil {
		notify("Cannot open the dashboard", err.Error())
	}
}

// systemProxyModes are the tray's system proxy items, in v2rayN's order.
var systemProxyModes = []struct{ mode, label, tip string }{
	{config.SystemProxyClear, "Clear system proxy", "Browsers and apps connect directly again"},
	{config.SystemProxySet, "Set system proxy", "Browsers and apps that use the system's proxy setting go through the VPN while it runs"},
}

// setSystemProxyMode stores the system proxy mode; refresh applies it.
func (a *trayApp) setSystemProxyMode(mode string) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := a.client.SetSystemProxy(ctx, mode); err != nil {
		notify("System proxy", err.Error())
		return
	}
	a.refresh()
}

func (a *trayApp) restartProxy() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := a.client.RestartProxy(ctx); err != nil {
		notify("Restart failed", err.Error())
		return
	}
	a.refresh()
}
