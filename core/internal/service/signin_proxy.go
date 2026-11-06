package service

import (
	"net/http"
	"sync"

	"github.com/armanlife/arman-vpn-client/core/internal/controlplane"
	"github.com/armanlife/arman-vpn-client/core/internal/logx"
	"github.com/armanlife/arman-vpn-client/core/internal/signinproxy"
)

// signInProxy holds the browser sign-in's proxy (package signinproxy):
// started the first time the app opens the sign-in page, and kept on its
// port while the core runs, since a Windows browser view keeps the proxy it
// was started with.
type signInProxy struct {
	mu     sync.Mutex
	server *signinproxy.Server
}

// open starts the proxy when it does not run (on preferredPort if it can),
// arms it, and returns its address.
func (p *signInProxy) open(preferredPort int) (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.server == nil {
		server, err := signinproxy.Listen(preferredPort, controlplane.DialContext)
		if err != nil {
			return "", err
		}
		p.server = server
		logx.Info("sign-in proxy listening listen=%s", server.Addr())
	}
	p.server.Arm()
	return p.server.Addr(), nil
}

// shut disarms the proxy: the sign-in page closed.
func (p *signInProxy) shut() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.server != nil {
		p.server.Disarm()
	}
}

// close stops the proxy for good: the core stops.
func (p *signInProxy) close() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.server != nil {
		p.server.Close()
		p.server = nil
	}
}

// handleSignInProxyOpen arms the browser sign-in's proxy and gives its
// address. Only the app on this device, holding the local token, may ask:
// the proxy is for its own browser view.
func (s *dashboardServer) handleSignInProxyOpen(w http.ResponseWriter, r *http.Request) {
	if !s.d.hasLocalToken(r) {
		writeError(w, http.StatusForbidden, "only the app on this device can use the sign-in proxy")
		return
	}
	var in struct {
		// Port is the port the app's browser view was started with, if
		// any; the proxy takes it again when it can.
		Port int `json:"port"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	address, err := s.d.signInProxy.open(in.Port)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "starting the sign-in proxy: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"address": address})
}

// handleSignInProxyClose disarms the proxy: the sign-in page closed.
func (s *dashboardServer) handleSignInProxyClose(w http.ResponseWriter, r *http.Request) {
	if !s.d.hasLocalToken(r) {
		writeError(w, http.StatusForbidden, "only the app on this device can use the sign-in proxy")
		return
	}
	s.d.signInProxy.shut()
	writeJSON(w, http.StatusOK, map[string]bool{"closed": true})
}
