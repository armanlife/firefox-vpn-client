package desktop

import (
	"context"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/service"
)

// Code shared by the desktop processes that host the service in-process:
// the tray icon (-tray) and the desktop app's core process (-app).

// statusPollTimeout bounds one status request.
const statusPollTimeout = 5 * time.Second

// pollStatus reads the service status through the local API.
func pollStatus(client *service.Client) (service.TrayStatus, error) {
	ctx, cancel := context.WithTimeout(context.Background(), statusPollTimeout)
	defer cancel()
	return client.Status(ctx)
}

// reachable reports whether a copy of the program answers the local API.
func reachable(client *service.Client, timeout time.Duration) bool {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	_, err := client.Status(ctx)
	return err == nil
}

// newHostedDaemon creates the service to run in this process. exit ends
// the process (POST /api/app/exit, which also makes /api/status report
// can_exit), and the dashboard's "Open folder" opens the file manager here.
func newHostedDaemon(paths service.DataPaths, verbose bool, exit func()) (*service.Daemon, error) {
	d, err := service.NewDaemon(paths, verbose)
	if err != nil {
		return nil, err
	}
	d.ExitApp = exit
	d.OpenFolder = openBrowser
	d.SystemProxySupported = systemProxySupported()
	return d, nil
}

// follow applies the system proxy mode from the service status every
// interval until ctx ends; an unreachable service counts as stopped, so
// this program's setting is removed. The tray applies the mode from its
// own polling instead.
func (s *systemProxySync) follow(ctx context.Context, client *service.Client, interval time.Duration) {
	if !systemProxySupported() {
		return
	}
	for {
		if st, err := pollStatus(client); err != nil {
			s.update(nil)
		} else {
			s.update(&st)
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(interval):
		}
	}
}
