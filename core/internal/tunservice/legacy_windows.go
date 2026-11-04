package tunservice

import (
	"errors"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc/mgr"

	"github.com/armanlife/arman-vpn-client/core/internal/logx"
)

// The service of the versions before 1.0.9, when the program was called
// Firefox VPN: its name and its folder in Program Files. The app of those
// versions talks to it, the new app does not; installing or removing the
// new service removes it (one administrator prompt, the first time TUN mode
// is used after the update).
const (
	legacyServiceName = "FirefoxVPNTun"
	legacyFolder      = "Firefox VPN"
)

// removeLegacy stops and removes the old service and its folder, if they
// are there; a failure is logged, not returned, as the new service does not
// need it.
func removeLegacy(m *mgr.Mgr) {
	if s, err := m.OpenService(legacyServiceName); err == nil {
		if err := stopService(s); err != nil {
			logx.Warn("TUN service: stopping the old service failed err=%s", logx.Err(err))
		}
		if err := s.Delete(); err != nil && !errors.Is(err, windows.ERROR_SERVICE_MARKED_FOR_DELETE) {
			logx.Warn("TUN service: removing the old service failed err=%s", logx.Err(err))
		}
		s.Close()
	}
	pf, err := windows.KnownFolderPath(windows.FOLDERID_ProgramFiles, 0)
	if err != nil {
		return
	}
	dir := filepath.Join(pf, legacyFolder)
	if _, err := os.Stat(filepath.Join(dir, "firefox-vpn-tun.exe")); err != nil {
		// Not the old service's folder (or gone already).
		return
	}
	var last error
	for range 20 {
		if last = os.RemoveAll(dir); last == nil {
			return
		}
		time.Sleep(500 * time.Millisecond)
	}
	logx.Warn("TUN service: removing the old service's folder failed err=%s", logx.Err(last))
}
