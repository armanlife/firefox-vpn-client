package desktop

import (
	"net"
	"sync"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/service"
)

// systemProxySync carries out the system_proxy mode (Windows, and GNOME's
// setting on Linux), in the
// tray's or the app mode's session:
//
//   - set points the system at the local proxy only while the proxy runs, so
//     stopping the program never leaves applications pointed at a closed
//     port; the previous setting comes back then.
//   - clear restores a setting this program made, then turns the system
//     proxy off once, when the mode is chosen (and when the host starts in
//     it), so a proxy set later by hand stays.
type systemProxySync struct {
	mu      sync.Mutex
	applied string // the proxy address this program set, "" for none
	mode    string // the last mode seen
}

// update carries out the mode for st (nil when the service is not
// reachable).
func (s *systemProxySync) update(st *service.TrayStatus) {
	if !systemProxySupported() {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	ours, want := "", ""
	if st != nil && st.Proxy != nil {
		ours = localProxyAddress(st.Proxy.Listen)
		if st.State.Phase == service.PhaseRunning && st.SystemProxy == config.SystemProxySet {
			want = ours
		}
	}

	// Remove this program's setting that is no longer wanted: what this
	// copy set, and what an earlier copy may have left behind for this
	// address (only when it is not wanted now, or the current setting
	// would be undone on every refresh).
	if s.applied != "" && s.applied != want {
		if err := restoreSystemProxy(s.applied); err != nil {
			logx.Warn("restoring the system proxy setting failed err=%s", logx.Err(err))
		} else if want == "" {
			logx.Info("system proxy setting restored")
		}
	}
	if ours != "" && ours != want {
		if err := restoreSystemProxy(ours); err != nil {
			logx.Warn("restoring the system proxy setting failed err=%s", logx.Err(err))
		}
	}
	if st != nil && st.SystemProxy != s.mode {
		if st.SystemProxy == config.SystemProxyClear {
			if err := clearSystemProxy(); err != nil {
				logx.Warn("clearing the system proxy setting failed err=%s", logx.Err(err))
			} else {
				logx.Info("system proxy cleared")
			}
		}
		s.mode = st.SystemProxy
	}
	if want != "" && want != s.applied {
		if err := setSystemProxy(want); err != nil {
			logx.Warn("setting the system proxy failed err=%s", logx.Err(err))
			want = ""
		} else {
			logx.Info("system proxy set to the local proxy address=%s", want)
		}
	}
	s.applied = want
}

// active reports whether this program's setting is in place now.
func (s *systemProxySync) active() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.applied != ""
}

// clear restores the user's proxy setting if this program set it.
func (s *systemProxySync) clear() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.applied == "" {
		return
	}
	if err := restoreSystemProxy(s.applied); err != nil {
		logx.Warn("restoring the system proxy setting failed err=%s", logx.Err(err))
	}
	s.applied = ""
}

// localProxyAddress is the address applications on this computer use for
// a proxy listening on listen.
func localProxyAddress(listen string) string {
	host, port, err := net.SplitHostPort(listen)
	if err != nil {
		return ""
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	return net.JoinHostPort(host, port)
}
