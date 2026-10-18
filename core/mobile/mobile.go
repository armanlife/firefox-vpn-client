// Package mobile is the gomobile entry point of the core: the Android app
// (and later other app shells) starts and stops the same daemon the
// desktop binary runs, with the data folder the app chooses. The app then
// talks to it through the dashboard's HTTP API on loopback, as the desktop
// tray does.
//
// Build: gomobile bind -target=android -androidapi 24 -o ../app/android/app/libs/core.aar ./mobile
package mobile

import (
	"context"
	"errors"
	"net"
	"strconv"
	"strings"
	"sync"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/service"
	"github.com/armanlife/firefox-vpn-client/core/internal/tun"
)

var (
	mu      sync.Mutex
	running *service.Daemon
	done    chan struct{}
	tunnel  *tun.Tunnel
)

// tunMTU is the VPN interface's MTU; the app sets the same.
const tunMTU = 1500

// Start runs the daemon with its data in dataDir (created when missing),
// with the proxy on or off (SetOn). It returns once the daemon is started;
// Run continues in the background.
func Start(dataDir string, on bool) error {
	mu.Lock()
	defer mu.Unlock()
	if running != nil {
		return errors.New("already running")
	}
	paths, err := service.ResolveDataPaths(dataDir)
	if err != nil {
		return err
	}
	if err := useAndroidRoots(paths.Dir); err != nil {
		return err
	}
	if err := neverSleep(paths.Config); err != nil {
		return err
	}
	d, err := service.NewDaemon(paths, false)
	if err != nil {
		return err
	}
	if !on {
		d.Off()
	}
	running, done = d, make(chan struct{})
	finished := done
	go func() {
		defer close(finished)
		_ = d.Run()
	}()
	return nil
}

// Stop shuts the daemon down and waits for it (bounded by the daemon).
func Stop() {
	StopTun()
	mu.Lock()
	d, finished := running, done
	running, done = nil, nil
	mu.Unlock()
	if d == nil {
		return
	}
	d.Shutdown()
	<-finished
}

// SetOn turns the proxy on or off; the daemon and its API keep running.
func SetOn(on bool) {
	mu.Lock()
	d := running
	mu.Unlock()
	if d != nil {
		d.SetOn(on)
	}
}

// NetworkChanged tells the core about Android's network: connected or
// not, after a change (Daemon.NetworkChanged).
func NetworkChanged(connected bool) {
	mu.Lock()
	d := running
	mu.Unlock()
	if d != nil {
		d.NetworkChanged(connected)
	}
}

// DirectApps lists, one per line, the apps of the routing region that the
// VPN leaves out (Daemon.DirectApps).
func DirectApps() string {
	mu.Lock()
	d := running
	mu.Unlock()
	if d == nil {
		return ""
	}
	return strings.Join(d.DirectApps(), "\n")
}

// ExitCountry is the country code the traffic leaves from, or "" while it
// is unknown (Daemon.ExitCountry).
func ExitCountry() string {
	mu.Lock()
	d := running
	mu.Unlock()
	if d == nil {
		return ""
	}
	return d.ExitCountry()
}

// ProxyAddress is where apps on this phone reach the proxy, such as
// 127.0.0.1:10810 (Daemon.ProxyEndpoint); "" when the core does not run.
// The notification shows it in proxy mode.
func ProxyAddress() string {
	mu.Lock()
	d := running
	mu.Unlock()
	if d == nil {
		return ""
	}
	addr, _, _ := d.ProxyEndpoint()
	return addr
}

// neverSleep sets proxy.idle_sleep to 0 in the config at path: the phone
// keeps its connection to Mozilla open while it is on (the user turned the
// whole phone's VPN on), and the app does not offer the setting there.
func neverSleep(path string) error {
	cfg, _, err := config.Load(path)
	if err != nil {
		return err
	}
	if cfg.Proxy.IdleSleep == 0 {
		return nil
	}
	cfg.Proxy.IdleSleep = 0
	return config.Save(path, cfg)
}

// Speed is the proxy's current speed in bytes per second, "down,up" (a
// few seconds' average); "0,0" while it is off. The notification shows it
// when the user asked for it.
func Speed() string {
	mu.Lock()
	d := running
	mu.Unlock()
	if d == nil {
		return "0,0"
	}
	down, up := d.Speed()
	return strconv.FormatInt(down, 10) + "," + strconv.FormatInt(up, 10)
}

// Running reports whether the daemon was started and not stopped.
func Running() bool {
	mu.Lock()
	defer mu.Unlock()
	return running != nil
}

// StartTun takes over the VPN's TUN device fd (Android's VpnService): the
// phone's TCP connections go through the proxy, DNS is answered with fake
// addresses that stand for names, and other UDP is refused. The fd is
// closed by StopTun. The app must exclude itself from the VPN, so the
// core's own connections do not loop back into it.
func StartTun(fd int32) error {
	mu.Lock()
	defer mu.Unlock()
	d := running
	if d == nil {
		return errors.New("the core does not run")
	}
	if tunnel != nil {
		tunnel.Stop()
		tunnel = nil
	}
	dial := func(ctx context.Context, target string) (net.Conn, error) {
		// Read each time: the port or the login may have changed.
		addr, user, password := d.ProxyEndpoint()
		dialer, err := tun.SOCKS5Dialer(addr, user, password)
		if err != nil {
			return nil, err
		}
		return dialer(ctx, target)
	}
	t, err := tun.Start(int(fd), tunMTU, dial, d.TunnelAllows, tun.NewFakeDNS())
	if err != nil {
		return err
	}
	tunnel = t
	return nil
}

// StopTun ends the VPN's stack and closes its device.
func StopTun() {
	mu.Lock()
	t := tunnel
	tunnel = nil
	mu.Unlock()
	if t != nil {
		t.Stop()
	}
}
