package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/accounts"
	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/netstate"
	"github.com/armanlife/firefox-vpn-client/core/internal/proxy"
	"github.com/armanlife/firefox-vpn-client/core/internal/serverlist"
	"github.com/armanlife/firefox-vpn-client/core/internal/version"
)

type proxyView struct {
	Listen          string    `json:"listen"`
	Upstream        string    `json:"upstream"`
	CountryCode     string    `json:"country_code"`
	CountryName     string    `json:"country_name"`
	CityName        string    `json:"city_name"`
	SelectionSource string    `json:"selection_source"`
	Transport       string    `json:"transport"`
	StartedAt       time.Time `json:"started_at"`
	// LoginRequired is set when SOCKS clients must authenticate.
	LoginRequired bool `json:"login_required"`
	// SleepingSince is set while the proxy holds no upstream session:
	// from its start until it is first used, and after proxy.idle_sleep.
	// Zero while connected to Mozilla.
	SleepingSince time.Time `json:"sleeping_since,omitzero"`
	// WakeError is why the last attempt to connect to Mozilla for a
	// connection or a test failed (at WakeFailedAt); empty after a
	// successful one.
	WakeError    string    `json:"wake_error,omitempty"`
	WakeFailedAt time.Time `json:"wake_failed_at,omitzero"`
}

type exitView struct {
	IPv4        string `json:"ipv4,omitempty"`
	IPv6        string `json:"ipv6,omitempty"`
	CountryCode string `json:"country_code"`
	// CountryName is the name the server list gives the country code.
	CountryName string `json:"country_name,omitempty"`
	City        string `json:"city,omitempty"`
	Network     string `json:"network,omitempty"`
	ProbeHost   string `json:"probe_host"`
	LatencyMS   int64  `json:"latency_ms"`
}

type AccountView struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Email    string `json:"email"`
	Position int    `json:"position"`
	Enabled  bool   `json:"enabled"`
	Active   bool   `json:"active"`
	Status   string `json:"status"`
	Reason   string `json:"reason,omitempty"`
	// ReasonCode and ReasonDetail say the same for the apps, which put it
	// in their own words (accounts.Why).
	ReasonCode   string          `json:"reason_code,omitempty"`
	ReasonDetail string          `json:"reason_detail,omitempty"`
	RetryAt      time.Time       `json:"retry_at,omitzero"`
	AddedAt      time.Time       `json:"added_at"`
	Usage        *accounts.Usage `json:"usage,omitempty"`
	UsedPercent  float64         `json:"used_percent"`
	// HasPassword is set when the password is stored (never the password).
	HasPassword      bool `json:"has_password"`
	DeviceRegistered bool `json:"device_registered"`
}

type StatusView struct {
	State engineState `json:"state"`
	Proxy *proxyView  `json:"proxy,omitempty"`
	// Selection is the chosen location even while the proxy is off:
	// proxy.country ("" recommended, "fastest", or a country), and
	// SelectionName the server list's name for a country.
	Selection string `json:"selection"`
	// NetworkChangedAt is when the phone last reported a network change:
	// a connection test before it says nothing about the connection now.
	NetworkChangedAt time.Time `json:"network_changed_at,omitzero"`
	// NoNetwork: the phone reported that no network is connected, so the
	// app says so at once instead of waiting for a test to fail.
	NoNetwork     bool                        `json:"no_network,omitempty"`
	SelectionName string                      `json:"selection_name,omitempty"`
	Pass          *proxy.RuntimeStatus        `json:"pass,omitempty"`
	ActiveAccount *AccountView                `json:"active_account,omitempty"`
	Exit          *exitView                   `json:"exit,omitempty"`
	LastTest      *proxy.ConnectionTestResult `json:"last_test,omitempty"`
	Accounts      map[string]int              `json:"accounts"`
	Threshold     float64                     `json:"switch_threshold_percent"`
	Dashboard     map[string]any              `json:"dashboard"`
	DataDir       string                      `json:"data_dir"`
	DNS           string                      `json:"dns"`
	Version       string                      `json:"version"`
	// CanExit is set when POST /app/exit can end the hosting process.
	CanExit bool `json:"can_exit"`
	// SystemProxy mirrors system_proxy.mode; SystemProxySupported is set
	// on Windows, where the tray icon applies it.
	SystemProxy          string `json:"system_proxy"`
	SystemProxySupported bool   `json:"system_proxy_supported"`
	// OpenFolderRequest counts the dashboard's requests to open the data
	// folder, for the tray to carry out.
	OpenFolderRequest uint64 `json:"open_folder_request"`
	// Traffic is what clients sent and received since the proxy started,
	// and the current speed.
	Traffic *proxy.Traffic `json:"traffic,omitempty"`
	// Notices are requests refused in the last noticeWindow because of a
	// limit (a port, UDP), for the dashboard to explain.
	Notices []proxy.Notice `json:"notices,omitempty"`
}

// noticeWindow is how long the dashboard shows a refused request.
const noticeWindow = 5 * time.Minute

func (s *dashboardServer) handleStatus(w http.ResponseWriter, r *http.Request) {
	view, err := s.d.StatusView()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, view)
}

// StatusView summarizes the service for the dashboard and the terminal
// screen.
func (d *Daemon) StatusView() (StatusView, error) {
	cfg := d.config()
	d.mu.Lock()
	view := StatusView{State: d.state, LastTest: d.lastTest, DataDir: d.paths.Dir, Threshold: cfg.Accounts.SwitchThresholdPercent}
	view.DNS = dnsDescription(cfg.DNS)
	view.Version = version.Current
	view.CanExit = d.ExitApp != nil
	view.OpenFolderRequest = d.folderRequests.Load()
	view.SystemProxy = cfg.SystemProxy.Mode
	view.Selection = cfg.Proxy.Country
	view.NetworkChangedAt = d.networkChangedAt
	view.NoNetwork = netstate.ReportedDown()
	if code := strings.ToUpper(cfg.Proxy.Country); len(code) == 2 {
		view.SelectionName = d.countryNameLocked(code)
	}
	view.SystemProxySupported = runtime.GOOS == "windows" || d.SystemProxySupported
	view.Notices = d.notices.Since(time.Now().Add(-noticeWindow))
	engine := d.engine
	if engine != nil {
		traffic := engine.routed.Traffic()
		view.Traffic = &traffic
	}
	if d.exit != nil && engine != nil {
		view.Exit = &exitView{IPv4: d.exit.IPv4, IPv6: d.exit.IPv6, CountryCode: d.exit.CountryCode, CountryName: d.countryNameLocked(d.exit.CountryCode), City: d.exit.City, Network: d.exit.Network, ProbeHost: d.exit.ProbeHost, LatencyMS: d.exit.Latency.Milliseconds()}
	}
	d.mu.Unlock()

	if engine != nil {
		if controller := engine.currentController(); controller != nil {
			status := controller.CurrentStatus("")
			view.Pass = &status
		}
		selected, source := engine.selection()
		view.Proxy = &proxyView{
			SleepingSince:   engine.asleepSince(),
			Listen:          engine.listener.Addr().String(),
			Upstream:        selected.Addr,
			CountryCode:     selected.CountryCode,
			CountryName:     selected.CountryName,
			CityName:        selected.CityName,
			SelectionSource: source,
			Transport:       engine.currentTransport(),
			StartedAt:       engine.startedAt,
			LoginRequired:   cfg.Proxy.Username != "",
		}
		if at, err := engine.wakeFailure(); err != nil {
			view.Proxy.WakeError, view.Proxy.WakeFailedAt = err.Error(), at
			if hint := proxy.GuardianFailureHint(err); hint != "" {
				view.Proxy.WakeError += ". " + hint
			}
		}
	}
	list, err := d.accountViews()
	if err != nil {
		return StatusView{}, err
	}
	view.Accounts = map[string]int{"total": len(list)}
	for i := range list {
		acc := list[i]
		if !acc.Enabled {
			view.Accounts["disabled"]++
			continue
		}
		view.Accounts[acc.Status]++
		if acc.Active {
			view.ActiveAccount = &list[i]
		}
	}
	view.Dashboard = map[string]any{
		"listen":                      cfg.Dashboard.Listen,
		"login_required":              cfg.Dashboard.Username != "",
		"exposed_without_login":       dashboardExposedWithoutLogin(cfg),
		"plaintext_over_network":      !hostIsLoopbackListen(cfg.Dashboard.Listen),
		"socks_exposed_without_login": cfg.Proxy.Username == "" && !hostIsLoopbackListen(cfg.Proxy.Listen),
	}
	return view, nil
}

// accountViews lists every stored account in priority order.
func (d *Daemon) accountViews() ([]AccountView, error) {
	list, err := d.store.List()
	if err != nil {
		return nil, err
	}
	byID := make(map[string]accounts.Account, len(list))
	for _, acc := range list {
		byID[acc.ID] = acc
	}
	active, hasActive := d.mgr.Active()
	cfg := d.config()
	views := make([]AccountView, 0, len(cfg.Accounts.Order))
	for i, ref := range cfg.Accounts.Order {
		acc, ok := byID[ref.ID]
		if !ok {
			continue
		}
		v := AccountView{
			ID: acc.ID, Name: acc.Name(), Email: acc.Email, Position: i + 1, Enabled: ref.Enabled,
			HasPassword: d.store.HasPassword(acc.ID), DeviceRegistered: acc.DeviceID != "",
			Active: hasActive && active.ID == acc.ID && ref.Enabled, Status: string(acc.Status),
			Reason: acc.Reason, ReasonCode: acc.ReasonCode, ReasonDetail: acc.ReasonDetail,
			RetryAt: acc.RetryAt, AddedAt: acc.AddedAt, Usage: acc.Usage,
		}
		if acc.Usage != nil && !acc.Usage.Unlimited && acc.Usage.LimitBytes > 0 {
			v.UsedPercent = float64(acc.Usage.UsedBytes()) * 100 / float64(acc.Usage.LimitBytes)
		}
		views = append(views, v)
	}
	return views, nil
}

func (s *dashboardServer) handleAccounts(w http.ResponseWriter, r *http.Request) {
	list, err := s.d.accountViews()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"accounts":                 list,
		"switch_threshold_percent": s.d.config().Accounts.SwitchThresholdPercent,
	})
}

func (s *dashboardServer) handleAccountOrder(w http.ResponseWriter, r *http.Request) {
	var in struct {
		IDs []string `json:"ids"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	respondResult(w, s.d.setAccountOrder(in.IDs))
}

func (s *dashboardServer) handleAccountActivate(w http.ResponseWriter, r *http.Request) {
	respondResult(w, s.d.activateAccount(r.PathValue("id")))
}

func (s *dashboardServer) handleAccountEnabled(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Enabled bool `json:"enabled"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	respondResult(w, s.d.setAccountEnabled(r.PathValue("id"), in.Enabled))
}

func (s *dashboardServer) handleAccountRefresh(w http.ResponseWriter, r *http.Request) {
	respondResult(w, s.d.refreshAccountUsage(r.PathValue("id")))
}

func (s *dashboardServer) handleAccountRemove(w http.ResponseWriter, r *http.Request) {
	respondResult(w, s.d.removeAccount(r.PathValue("id")))
}

func (s *dashboardServer) handleSignInStart(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
		// AccountID signs an existing account in again with its stored
		// password, so only a confirmation code may be asked for.
		AccountID string `json:"account_id"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if in.AccountID != "" {
		acc, err := s.d.store.Get(in.AccountID)
		if err != nil {
			writeError(w, http.StatusNotFound, "unknown account")
			return
		}
		password, err := s.d.store.Password(acc.ID)
		if err != nil {
			writeError(w, http.StatusConflict, "no stored password for this account; enter it")
			return
		}
		in.Email, in.Password = acc.Email, password
	}
	view, err := s.d.signins.start(in.Email, in.Password)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusAccepted, view)
}

func (s *dashboardServer) handleSignInGet(w http.ResponseWriter, r *http.Request) {
	session, ok := s.d.signins.get(r.PathValue("id"))
	if !ok {
		writeError(w, http.StatusNotFound, "unknown sign-in")
		return
	}
	writeJSON(w, http.StatusOK, session.snapshot())
}

func (s *dashboardServer) handleSignInAnswer(w http.ResponseWriter, r *http.Request) {
	session, ok := s.d.signins.get(r.PathValue("id"))
	if !ok {
		writeError(w, http.StatusNotFound, "unknown sign-in")
		return
	}
	var in struct {
		Value string `json:"value"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if err := session.answer(in.Value); err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, session.snapshot())
}

func (s *dashboardServer) handleSignInCancel(w http.ResponseWriter, r *http.Request) {
	if session, ok := s.d.signins.get(r.PathValue("id")); ok {
		session.cancel()
	}
	writeJSON(w, http.StatusOK, map[string]bool{"cancelled": true})
}

type settingsView struct {
	Config        config.Config `json:"config"`
	LoginRequired bool          `json:"dashboard_login_required"`
	DataDir       string        `json:"data_dir"`
	// ProgramDir is the folder of the running core's executable.
	ProgramDir string `json:"program_dir,omitempty"`
}

// programDir is the folder of this executable; empty when unknown.
func programDir() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	if real, err := filepath.EvalSymlinks(exe); err == nil {
		exe = real
	}
	return filepath.Dir(exe)
}

func (s *dashboardServer) handleSettingsGet(w http.ResponseWriter, r *http.Request) {
	cfg := s.d.config()
	required := cfg.Dashboard.Username != ""
	cfg.Dashboard.PasswordHash = ""
	cfg.Accounts.Order = nil
	writeJSON(w, http.StatusOK, settingsView{Config: cfg, LoginRequired: required, DataDir: s.d.paths.Dir, ProgramDir: programDir()})
}

func (s *dashboardServer) handleSettingsPut(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Config            config.Config `json:"config"`
		DashboardPassword *string       `json:"dashboard_password"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	change, err := s.d.updateSettings(in.Config, in.DashboardPassword)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"saved": true, "proxy_restarted": change.restartEngine, "dashboard_moved": change.restartDashboard})
	if change.restartDashboard {
		listen := in.Config.Dashboard.Listen
		go func() {
			time.Sleep(500 * time.Millisecond)
			s.moveTo(listen)
		}()
	}
}

type locationView struct {
	Code        string `json:"code"`
	Name        string `json:"name"`
	City        string `json:"city,omitempty"`
	Server      string `json:"server,omitempty"`
	Locked      bool   `json:"locked"`
	Recommended bool   `json:"recommended"`
	PingMS      int64  `json:"ping_ms,omitempty"`
	PingError   string `json:"ping_error,omitempty"`
}

func (s *dashboardServer) handleLocations(w http.ResponseWriter, r *http.Request) {
	s.d.mu.Lock()
	countries := s.d.countries
	s.d.mu.Unlock()
	if len(countries) == 0 {
		countries = s.d.refreshLocations(s.d.config())
	}
	seen := make(map[string]bool)
	var out []locationView
	for _, candidate := range proxy.ConnectCandidates(countries) {
		code := strings.ToUpper(candidate.CountryCode)
		if code == "" || seen[code] {
			continue
		}
		seen[code] = true
		out = append(out, locationView{Code: code, Name: candidate.CountryName, City: candidate.CityName, Server: candidate.Addr, Locked: candidate.Locked, Recommended: candidate.IsRecommended()})
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Recommended != out[j].Recommended {
			return out[i].Recommended
		}
		return out[i].Name < out[j].Name
	})
	pings, pingedAt := s.d.lastPings()
	byCode := make(map[string]proxy.LocationPing, len(pings))
	for _, p := range pings {
		byCode[p.Code] = p
	}
	for i := range out {
		if p, ok := byCode[out[i].Code]; ok {
			out[i].PingMS, out[i].PingError = p.PingMS, p.Error
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"locations": out, "pinged_at": pingedAt, "firefox_version": s.d.knownFirefoxVersion()})
}

// handleLocationPing measures every location's latency; the result is
// sorted by latency and kept for GET /locations.
func (s *dashboardServer) handleLocationPing(w http.ResponseWriter, r *http.Request) {
	var in struct {
		// Codes limits the test to these locations (the dashboard's tab).
		Codes []string `json:"codes"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	pings, pingedAt, err := s.d.PingAll(r.Context(), in.Codes)
	if err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"locations": pings, "pinged_at": pingedAt, "target": proxy.PingTarget})
}

func (s *dashboardServer) handleConnectionTest(w http.ResponseWriter, r *http.Request) {
	result, err := s.d.ConnectionTest()
	if err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, result)
}

// countryNameLocked names a country code from the server list, or returns
// the code; d.mu is held.
func (d *Daemon) countryNameLocked(code string) string {
	for _, c := range d.countries {
		if strings.EqualFold(c.Code, code) && c.Name != "" {
			return c.Name
		}
	}
	return code
}

// errProxyNotRunning reports an action that needs the running proxy.
var errProxyNotRunning = errors.New("the proxy is not running")

// ConnectionTest runs the connection test through the running engine,
// waking it when it sleeps, and keeps the result for the status view.
func (d *Daemon) ConnectionTest() (proxy.ConnectionTestResult, error) {
	engine := d.currentEngine()
	if engine == nil {
		return proxy.ConnectionTestResult{}, errProxyNotRunning
	}
	controller, release, err := d.useController(engine, wakeForTest)
	if err != nil {
		return proxy.ConnectionTestResult{}, err
	}
	defer release()
	return d.runConnectionTest(engine, controller, "requested"), nil
}

// autoTest runs the connection test by itself when the proxy first
// connected to Mozilla or its upstream session was replaced, so Overview
// has a current result and public IP. One runs at a time; a test for an engine that has
// stopped meanwhile is skipped.
func (d *Daemon) autoTest(engine *proxyEngine, why string) {
	if !d.autoTesting.CompareAndSwap(false, true) {
		return
	}
	defer d.autoTesting.Store(false)
	if d.currentEngine() != engine {
		return
	}
	// An automatic test never wakes a sleeping proxy.
	controller := engine.reserve()
	if controller == nil {
		return
	}
	defer engine.releaseFunc()()
	d.runConnectionTest(engine, controller, why)
}

// exitCheckTimeout and connectTimeout are config.ExitCheckTimeout and
// config.ConnectTimeout; tests change them (0 skips the public IP check).
var (
	exitCheckTimeout = config.ExitCheckTimeout
	connectTimeout   = config.ConnectTimeout
)

// runConnectionTest tests engine and records the result and, from it, the
// public IP.
func (d *Daemon) runConnectionTest(engine *proxyEngine, controller *proxy.Controller, why string) proxy.ConnectionTestResult {
	result := proxy.RunConnectionTest(controller, proxy.ConnectionTestURL, exitCheckTimeout, proxy.ConnectionTestTimeout)
	exit := result.Exit()
	d.mu.Lock()
	d.lastTest = &result
	if exit.IP() != "" {
		d.exit = &exit
	}
	d.mu.Unlock()
	if !result.OK {
		logx.Warn("connection test failed reason=%s err=%s", why, result.Error)
		return result
	}
	logx.Info("connection test passed reason=%s total_ms=%d tunnel_ms=%d ipv4=%s ipv6=%s place=%q", why, result.TotalMS, result.TunnelMS, result.ExitIPv4, result.ExitIPv6, exit.Place())
	if selected, _ := engine.selection(); selected.CountryCode != "" && exit.CountryCode != "" && !strings.EqualFold(selected.CountryCode, exit.CountryCode) && !selected.IsRecommended() {
		code := selected.CountryCode
		logx.Warn("public IP country differs from the selected location configured_country_code=%s public_ip_country_code=%s", code, exit.CountryCode)
	}
	return result
}

// handleAppExit stops the proxy and ends the process hosting it (the tray).
// Only local clients holding the local token may call it, so a browser on
// another device cannot shut down a dashboard it would then lose.
func (s *dashboardServer) handleAppExit(w http.ResponseWriter, r *http.Request) {
	if !s.d.hasLocalToken(r) {
		writeError(w, http.StatusForbidden, "only the program on this computer can exit it")
		return
	}
	if s.d.ExitApp == nil {
		writeError(w, http.StatusConflict, "this copy runs as the Windows service; remove the service to stop it")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"exiting": true})
	go s.d.ExitApp()
}

// handleSystemProxy sets system_proxy.mode (set or clear; config validation
// refuses anything else); the tray icon or the app mode applies it to
// Windows.
func (s *dashboardServer) handleSystemProxy(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Mode string `json:"mode"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if err := s.d.SetSystemProxy(in.Mode); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"mode": in.Mode})
}

// handlePower turns the proxy on or off (Daemon.SetOn): off closes its
// port and, with the system proxy set, gives Windows its previous setting
// back (systemProxySync); the API keeps running. It is not stored.
func (s *dashboardServer) handlePower(w http.ResponseWriter, r *http.Request) {
	var in struct {
		On bool `json:"on"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	s.d.SetOn(in.On)
	writeJSON(w, http.StatusOK, map[string]bool{"on": in.On})
}

// handleOpenFolder shows the data folder in the file manager of this
// computer's desktop. Only a browser on this computer may ask: from
// another device it would open on a screen nobody sees.
func (s *dashboardServer) handleOpenFolder(w http.ResponseWriter, r *http.Request) {
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err != nil || !net.ParseIP(host).IsLoopback() {
		writeError(w, http.StatusForbidden, "the folder can only be opened from a browser on this computer")
		return
	}
	if open := s.d.OpenFolder; open != nil {
		if err := open(s.d.paths.Dir); err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"result": "opened"})
		return
	}
	s.d.folderRequests.Add(1)
	writeJSON(w, http.StatusOK, map[string]string{"result": "asked the tray icon"})
}

// SetSystemProxy stores system_proxy.mode.
func (d *Daemon) SetSystemProxy(mode string) error {
	cfg := d.config()
	if cfg.SystemProxy.Mode == mode {
		return nil
	}
	cfg.SystemProxy.Mode = mode
	if _, err := d.updateSettings(cfg, nil); err != nil {
		return err
	}
	logx.Info("system proxy mode changed mode=%s", mode)
	return nil
}

// handleSetLocation selects a location: a country code, "fastest", or ""
// for the recommended location. It clears an exact server.
func (s *dashboardServer) handleSetLocation(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Country string `json:"country"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if err := s.d.SetLocation(in.Country); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"saved": true})
}

// SetLocation stores proxy.country and restarts the engine when it changed.
func (d *Daemon) SetLocation(country string) error {
	cfg := d.config()
	cfg.Proxy.Country = strings.TrimSpace(country)
	if strings.EqualFold(cfg.Proxy.Country, serverlist.RecommendedCountryCode) {
		cfg.Proxy.Country = ""
	}
	cfg.Proxy.Server = ""
	_, err := d.updateSettings(cfg, nil)
	return err
}

func (s *dashboardServer) handleProxyRestart(w http.ResponseWriter, r *http.Request) {
	s.d.RequestRestart()
	writeJSON(w, http.StatusOK, map[string]bool{"restarting": true})
}

func (s *dashboardServer) handleLogs(w http.ResponseWriter, r *http.Request) {
	after, _ := strconv.ParseUint(r.URL.Query().Get("after"), 10, 64)
	writeJSON(w, http.StatusOK, map[string]any{"entries": logx.Logs.Since(after)})
}

// handleLogStream streams new log entries as server-sent events.
func (s *dashboardServer) handleLogStream(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "streaming unsupported")
		return
	}
	entries, unsubscribe := logx.Logs.Subscribe()
	defer unsubscribe()
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	keepalive := time.NewTicker(25 * time.Second)
	defer keepalive.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-keepalive.C:
			fmt.Fprint(w, ": keepalive\n\n")
			flusher.Flush()
		case entry := <-entries:
			data, _ := json.Marshal(entry)
			fmt.Fprintf(w, "id: %d\ndata: %s\n\n", entry.ID, data)
			flusher.Flush()
		}
	}
}

func respondResult(w http.ResponseWriter, err error) {
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func hostIsLoopbackListen(addr string) bool {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return false
	}
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
