package service

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"

	"golang.org/x/crypto/bcrypt"
)

//go:embed web
var webFiles embed.FS

const (
	sessionCookieName = "fvpn_session"
	// sessionLifetime is the longest a browser keeps a cookie (Chrome caps
	// cookie lifetimes at 400 days).
	sessionLifetime     = 400 * 24 * time.Hour
	failedLoginDelay    = time.Second
	maxRequestBodyBytes = 1 << 20
	minPasswordLength   = 6
)

// dashboardServer serves the web dashboard and its JSON API. Without a
// configured username it requires no login, which is meant for loopback
// use; with one, API calls need a session cookie from POST /api/session.
//
// A session cookie is signed rather than stored: "<expiry>.<HMAC-SHA256 of
// the expiry, username, and password hash>" under the data folder's
// session key (dashboard.key). It survives restarts and stays valid for
// sessionLifetime, until the username or password changes (which signs
// everyone out) or it is signed out.
type dashboardServer struct {
	d *Daemon

	mu       sync.Mutex
	server   *http.Server
	listener net.Listener
	// signedOut are cookies signed out since the start, until they expire.
	signedOut map[string]time.Time
}

func newDashboardServer(d *Daemon) *dashboardServer {
	return &dashboardServer{d: d, signedOut: make(map[string]time.Time)}
}

// sessionToken signs a session for cfg's login that ends at expiry.
func (s *dashboardServer) sessionToken(cfg config.Dashboard, expiry time.Time) string {
	stamp := strconv.FormatInt(expiry.Unix(), 10)
	mac := hmac.New(sha256.New, s.d.sessionKey)
	mac.Write([]byte(stamp + "\x00" + cfg.Username + "\x00" + cfg.PasswordHash))
	return stamp + "." + hex.EncodeToString(mac.Sum(nil))
}

// start listens on addr and serves in the background.
func (s *dashboardServer) start(addr string) error {
	ln, err := listenTCP(ListenerDashboard, addr)
	if err != nil {
		return err
	}
	srv := &http.Server{
		Handler:           s.handler(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       2 * time.Minute,
	}
	s.mu.Lock()
	s.server, s.listener = srv, ln
	s.mu.Unlock()
	go func() {
		if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logx.Error("dashboard stopped err=%s", logx.Err(err))
		}
	}()
	cfg := s.d.config()
	logx.Info("dashboard listening url=http://%s login_required=%v", displayAddr(ln.Addr().String()), cfg.Dashboard.Username != "")
	if dashboardExposedWithoutLogin(cfg) {
		logx.Warn("the dashboard is reachable from other devices without a login; set dashboard.username and a password")
	}
	return nil
}

// moveTo switches the dashboard to a new address, keeping the old one when
// the new address cannot be used.
func (s *dashboardServer) moveTo(addr string) {
	s.mu.Lock()
	old := s.server
	s.mu.Unlock()
	if err := s.start(addr); err != nil {
		logx.Error("moving the dashboard failed; keeping the previous address addr=%s err=%s", addr, logx.Err(err))
		return
	}
	if old != nil {
		_ = old.Close()
	}
}

// close stops the dashboard and ends open connections, including log
// streams.
func (s *dashboardServer) close() {
	s.mu.Lock()
	srv := s.server
	s.server, s.listener = nil, nil
	s.mu.Unlock()
	if srv != nil {
		_ = srv.Close()
	}
}

func (s *dashboardServer) handler() http.Handler {
	mux := http.NewServeMux()
	static, _ := fs.Sub(webFiles, "web")
	mux.Handle("GET /", http.FileServerFS(static))
	mux.HandleFunc("GET /flags/{file}", s.handleFlag)

	mux.HandleFunc("GET /api/session", s.handleSessionInfo)
	mux.HandleFunc("POST /api/session", s.handleLogin)
	mux.HandleFunc("DELETE /api/session", s.handleLogout)
	mux.HandleFunc("POST /api/dashboard/reset-login", s.handleResetLogin)
	mux.HandleFunc("POST /api/open-folder", s.handleOpenFolder)

	mux.HandleFunc("GET /api/status", s.handleStatus)
	mux.HandleFunc("POST /api/test", s.handleConnectionTest)
	mux.HandleFunc("POST /api/proxy/restart", s.handleProxyRestart)
	mux.HandleFunc("POST /api/system-proxy", s.handleSystemProxy)
	mux.HandleFunc("POST /api/power", s.handlePower)

	mux.HandleFunc("GET /api/accounts", s.handleAccounts)
	mux.HandleFunc("POST /api/accounts/order", s.handleAccountOrder)
	mux.HandleFunc("POST /api/accounts/{id}/activate", s.handleAccountActivate)
	mux.HandleFunc("POST /api/accounts/{id}/enabled", s.handleAccountEnabled)
	mux.HandleFunc("POST /api/accounts/{id}/refresh", s.handleAccountRefresh)
	mux.HandleFunc("DELETE /api/accounts/{id}", s.handleAccountRemove)

	mux.HandleFunc("POST /api/signin", s.handleSignInStart)
	mux.HandleFunc("GET /api/signin/{id}", s.handleSignInGet)
	mux.HandleFunc("POST /api/signin/{id}", s.handleSignInAnswer)
	mux.HandleFunc("DELETE /api/signin/{id}", s.handleSignInCancel)

	mux.HandleFunc("GET /api/settings", s.handleSettingsGet)
	mux.HandleFunc("PUT /api/settings", s.handleSettingsPut)
	mux.HandleFunc("GET /api/locations", s.handleLocations)
	mux.HandleFunc("POST /api/locations/ping", s.handleLocationPing)
	mux.HandleFunc("POST /api/location", s.handleSetLocation)
	mux.HandleFunc("POST /api/dns/test", s.handleDNSTest)
	mux.HandleFunc("GET /api/routing", s.handleRouting)
	mux.HandleFunc("POST /api/routing/update", s.handleRoutingUpdate)
	mux.HandleFunc("POST /api/routing/test", s.handleRoutingTest)
	mux.HandleFunc("POST /api/app/exit", s.handleAppExit)

	mux.HandleFunc("GET /api/logs", s.handleLogs)
	mux.HandleFunc("GET /api/logs/stream", s.handleLogStream)
	return s.guard(mux)
}

// guard applies the dashboard's request policy:
//   - without a login, only requests addressed to an IP literal or
//     "localhost" are served, which defeats DNS rebinding;
//   - state-changing requests must be JSON and same-origin, so ordinary
//     web pages cannot submit them (CSRF);
//   - with a login, API calls need a valid session cookie;
//   - a valid local token (X-Local-Token, read from the data folder by the
//     tray) replaces both the Host check and the login. Browsers cannot
//     attach that header cross-origin without a CORS preflight, which the
//     dashboard never grants.
func (s *dashboardServer) guard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'")
		if strings.HasPrefix(r.URL.Path, "/flags/") {
			h.Set("Cache-Control", "public, max-age=604800")
		} else {
			h.Set("Cache-Control", "no-store")
		}

		cfg := s.d.config()
		local := s.d.hasLocalToken(r)
		loginRequired := cfg.Dashboard.Username != "" && !local
		if !loginRequired && !local && !hostIsAddress(r.Host) {
			writeError(w, http.StatusForbidden, "open the dashboard by IP address or localhost")
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
				writeError(w, http.StatusUnsupportedMediaType, "requests must be JSON")
				return
			}
			if origin := r.Header.Get("Origin"); origin != "" && !originMatchesHost(origin, r.Host) {
				writeError(w, http.StatusForbidden, "cross-origin request refused")
				return
			}
			r.Body = http.MaxBytesReader(w, r.Body, maxRequestBodyBytes)
		}
		if loginRequired && strings.HasPrefix(r.URL.Path, "/api/") && r.URL.Path != "/api/session" && !s.validSession(r) {
			writeError(w, http.StatusUnauthorized, "login required")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *dashboardServer) handleSessionInfo(w http.ResponseWriter, r *http.Request) {
	cfg := s.d.config()
	required := cfg.Dashboard.Username != ""
	writeJSON(w, http.StatusOK, map[string]bool{
		"login_required": required,
		"authenticated":  !required || s.validSession(r),
	})
}

func (s *dashboardServer) handleLogin(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	cfg := s.d.config()
	if cfg.Dashboard.Username == "" {
		writeJSON(w, http.StatusOK, map[string]bool{"authenticated": true})
		return
	}
	userOK := subtle.ConstantTimeCompare([]byte(in.Username), []byte(cfg.Dashboard.Username)) == 1
	passOK := bcrypt.CompareHashAndPassword([]byte(cfg.Dashboard.PasswordHash), []byte(in.Password)) == nil
	if !userOK || !passOK {
		time.Sleep(failedLoginDelay)
		logx.Warn("dashboard login failed remote=%s", r.RemoteAddr)
		writeError(w, http.StatusUnauthorized, "wrong username or password")
		return
	}
	expiry := time.Now().Add(sessionLifetime)
	http.SetCookie(w, &http.Cookie{
		Name: sessionCookieName, Value: s.sessionToken(cfg.Dashboard, expiry), Path: "/", HttpOnly: true,
		SameSite: http.SameSiteStrictMode, MaxAge: int(sessionLifetime / time.Second), Expires: expiry,
	})
	writeJSON(w, http.StatusOK, map[string]bool{"authenticated": true})
}

func (s *dashboardServer) handleLogout(w http.ResponseWriter, r *http.Request) {
	if cookie, err := r.Cookie(sessionCookieName); err == nil {
		s.mu.Lock()
		for value, expiry := range s.signedOut {
			if time.Now().After(expiry) {
				delete(s.signedOut, value)
			}
		}
		s.signedOut[cookie.Value] = time.Now().Add(sessionLifetime)
		s.mu.Unlock()
	}
	http.SetCookie(w, &http.Cookie{Name: sessionCookieName, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, SameSite: http.SameSiteStrictMode})
	writeJSON(w, http.StatusOK, map[string]bool{"authenticated": false})
}

func (s *dashboardServer) validSession(r *http.Request) bool {
	cookie, err := r.Cookie(sessionCookieName)
	if err != nil {
		return false
	}
	stamp, _, ok := strings.Cut(cookie.Value, ".")
	unix, err := strconv.ParseInt(stamp, 10, 64)
	if !ok || err != nil || time.Now().After(time.Unix(unix, 0)) {
		return false
	}
	want := s.sessionToken(s.d.config().Dashboard, time.Unix(unix, 0))
	if !hmac.Equal([]byte(cookie.Value), []byte(want)) {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_, out := s.signedOut[cookie.Value]
	return !out
}

// handleResetLogin gives the dashboard a new random login. Only the
// program on this computer (the status screen, holding the local token)
// may call it: it is the way back in after a forgotten password.
func (s *dashboardServer) handleResetLogin(w http.ResponseWriter, r *http.Request) {
	if !s.d.hasLocalToken(r) {
		writeError(w, http.StatusForbidden, "only the program on this computer can reset the dashboard login")
		return
	}
	username, password, err := s.d.ResetDashboardLogin()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"username": username, "password": password})
}

// ResetDashboardLogin replaces the dashboard login with a random username
// and password and returns them; every signed-in browser is signed out.
func (d *Daemon) ResetDashboardLogin() (username, password string, err error) {
	username = "admin-" + randomText(4, "abcdefghijkmnpqrstuvwxyz23456789")
	password = randomText(16, "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789")
	cfg := d.config()
	cfg.Dashboard.Username = username
	if _, err := d.updateSettings(cfg, &password); err != nil {
		return "", "", err
	}
	logx.Info("dashboard login reset on this computer username=%s", username)
	return username, password, nil
}

// randomText returns n characters drawn from alphabet (which leaves out
// look-alikes such as 0, O, 1, l, and I).
func randomText(n int, alphabet string) string {
	out := make([]byte, n)
	for i := range out {
		k, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			panic(err) // crypto/rand does not fail on supported systems
		}
		out[i] = alphabet[k.Int64()]
	}
	return string(out)
}

// HashDashboardPassword returns the bcrypt hash stored in config.json.
func HashDashboardPassword(password string) (string, error) {
	if len(password) < minPasswordLength {
		return "", fmt.Errorf("the dashboard password must have at least %d characters", minPasswordLength)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

// hostIsAddress reports whether a Host header names an IP literal or
// localhost rather than a DNS name.
func hostIsAddress(host string) bool {
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	host = strings.Trim(host, "[]")
	return strings.EqualFold(host, "localhost") || net.ParseIP(host) != nil
}

func originMatchesHost(origin, host string) bool {
	u, err := url.Parse(origin)
	return err == nil && strings.EqualFold(u.Host, host)
}

// displayAddr turns an unspecified listen address into a usable URL host.
func displayAddr(addr string) string {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	if ip := net.ParseIP(host); ip != nil && ip.IsUnspecified() {
		host = "127.0.0.1"
	}
	return net.JoinHostPort(host, port)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request: "+err.Error())
		return false
	}
	return true
}
