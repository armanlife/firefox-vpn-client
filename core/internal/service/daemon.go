package service

import (
	"context"
	"errors"
	"fmt"
	"net"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/accounts"
	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/fxa"
	"github.com/armanlife/firefox-vpn-client/core/internal/guardian"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/netstate"
	"github.com/armanlife/firefox-vpn-client/core/internal/proxy"
	"github.com/armanlife/firefox-vpn-client/core/internal/routing"
	"github.com/armanlife/firefox-vpn-client/core/internal/securefile"
	"github.com/armanlife/firefox-vpn-client/core/internal/serverlist"
	"github.com/armanlife/firefox-vpn-client/core/internal/version"
)

// engineStartRetry spaces attempts to start the proxy after an error that
// is neither "no accounts" nor "every account reserved".
const engineStartRetry = 30 * time.Second

// MessageWaitingForNetwork is the state message while the proxy start
// waits for a network.
const MessageWaitingForNetwork = "Waiting for a network connection"

// networkConnected reports a connected network; tests replace it.
var networkConnected = netstate.Connected

// networkPoll is how often a wait for the network looks again; the check
// reads the adapter list and sends nothing. Tests shorten it.
var networkPoll = 2 * time.Second

// networkSettleRetry retries a failed start soon after the network
// connected, when DNS or DHCP may still be settling.
const networkSettleRetry = 5 * time.Second

// Engine phases reported to the dashboard.
const (
	PhaseStarting = "starting"
	PhaseRunning  = "running"
	PhaseWaiting  = "waiting"
	PhaseError    = "error"
	// PhaseOff: the app turned the proxy off (SetOn); the API still runs.
	PhaseOff = "off"
)

type engineState struct {
	Phase   string `json:"phase"`
	Message string `json:"message"`
	// Code names a problem a client can act on (CodeProxyPortInUse); it is
	// empty otherwise and cleared by the next state.
	Code string `json:"code,omitempty"`
	// Address is the listen address the code is about.
	Address string    `json:"address,omitempty"`
	Since   time.Time `json:"since"`
	RetryAt time.Time `json:"retry_at,omitzero"`
}

// Daemon owns the configuration, the accounts, the running proxy engine,
// and the dashboard. The dashboard keeps running while the proxy engine is
// stopped, waiting for an account, or restarting after a settings change.
type Daemon struct {
	paths DataPaths
	// notices outlives engine restarts, so the dashboard can still explain
	// a refused request after the proxy restarted.
	notices *proxy.Notices
	// sessionKey signs the dashboard's session cookies.
	sessionKey []byte
	// autoTesting is set while an automatic connection test runs.
	autoTesting atomic.Bool
	routing     routingState
	// wakeHook replaces wake in tests.
	wakeHook func(*proxyEngine) error
	// devicesOnce registers the accounts' devices after the first
	// connection to Mozilla (registerDevices).
	devicesOnce  sync.Once
	forceVerbose bool
	store        *accounts.Store
	mgr          *accounts.Manager
	pool         *proxy.AccountPool
	signins      *signInRegistry
	restart      chan struct{}
	stop         chan struct{}
	stopOnce     sync.Once
	finished     chan struct{}
	// LocalToken authorizes local clients (the tray) without the dashboard
	// login; it is regenerated at every start and stored in the data folder.
	localToken string
	// ExitApp ends the process that hosts this daemon (the tray or the
	// desktop app's core process); nil when the host cannot be ended that
	// way (the Windows service).
	ExitApp func()
	// RequireDashboard makes Run fail when the dashboard is disabled in
	// config.json: the desktop app reaches the service only through its API.
	RequireDashboard bool
	// OpenFolder, when set, shows a folder in the desktop's file manager;
	// the tray and the status screen set it when the service runs in their
	// process. A Windows service cannot reach the desktop, so it asks the
	// tray instead (folderRequests).
	OpenFolder func(dir string) error
	// folderRequests counts requests to open the data folder; the tray
	// opens it when the count in the status rises.
	folderRequests atomic.Uint64

	mu  sync.Mutex
	cfg config.Config
	// off keeps the proxy engine stopped (SetOn); Off sets it before Run.
	off       bool
	engine    *proxyEngine
	state     engineState
	countries []serverlist.Country
	exit      *proxy.ExitProbeResult
	lastTest  *proxy.ConnectionTestResult
	dashboard *dashboardServer
	pings     []proxy.LocationPing
	pingedAt  time.Time

	// ffVersion is the Firefox version the server list is evaluated for.
	ffVersion   string
	ffVersionAt time.Time

	// networkChangedAt is when the phone last reported a network change.
	networkChangedAt time.Time
	// flags guards downloading the flags the program does not carry
	// (flags.go).
	flags struct {
		mu     sync.Mutex
		failed map[string]time.Time
	}
	// pingMu serializes latency measurements.
	pingMu sync.Mutex
	// pingPass is the pass of measurements while the proxy is off, reused
	// until shortly before it expires; pingMu guards it.
	pingPass *guardian.ProxyPassInfo
}

func NewDaemon(paths DataPaths, forceVerbose bool) (*Daemon, error) {
	cfg, err := LoadConfig(paths, forceVerbose)
	if err != nil {
		return nil, err
	}
	store, order, err := OpenAccounts(paths, &cfg)
	if err != nil {
		return nil, err
	}
	mgr, err := accounts.NewManager(store, order, accounts.Policy{ThresholdPercent: cfg.Accounts.SwitchThresholdPercent}, paths.State)
	if err != nil {
		return nil, err
	}
	sessionKey, err := loadSessionKey(paths.SessionKey)
	if err != nil {
		return nil, fmt.Errorf("dashboard session key: %w", err)
	}
	d := &Daemon{
		paths:        paths,
		sessionKey:   sessionKey,
		notices:      &proxy.Notices{},
		routing:      routingState{wake: make(chan struct{}, 1)},
		forceVerbose: forceVerbose,
		store:        store,
		mgr:          mgr,
		pool:         proxy.NewAccountPool(store, mgr),
		restart:      make(chan struct{}, 1),
		stop:         make(chan struct{}),
		finished:     make(chan struct{}),
		cfg:          cfg,
		state:        engineState{Phase: PhaseStarting, Message: "Starting", Since: time.Now()},
	}
	d.signins = newSignInRegistry(d)
	d.loadSavedLocations()
	return d, nil
}

// loadSavedLocations shows the last server list fetched until the next one
// arrives, so the locations are there at once, also with no network.
func (d *Daemon) loadSavedLocations() {
	cached, _, err := serverlist.LoadCache(d.paths.ServerList)
	if err != nil {
		return
	}
	countries, _ := serverlist.Filter(cached, serverlist.Environment{FirefoxVersion: d.knownFirefoxVersion()})
	d.countries = countries
}

// Run starts the dashboard and supervises the proxy engine until Shutdown.
func (d *Daemon) Run() error {
	defer close(d.finished)
	cfg := d.config()
	logx.Info("service starting version=%s data_dir=%s accounts=%d switch_threshold=%g%%", version.Current, d.paths.Dir, d.mgr.Len(), cfg.Accounts.SwitchThresholdPercent)
	token, err := newLocalToken()
	if err != nil {
		return err
	}
	d.localToken = token
	if cfg.Dashboard.Enabled {
		d.dashboard = newDashboardServer(d)
		if err := d.dashboard.start(cfg.Dashboard.Listen); err != nil {
			// A taken address (*AddressInUseError) is returned as is: the
			// desktop app tells the user and offers another port.
			return fmt.Errorf("starting the dashboard: %w", err)
		}
		// Published only once this instance owns the dashboard address, so
		// a second instance that fails to start cannot replace it.
		if err := securefile.WritePrivate(d.paths.LocalToken, []byte(token)); err != nil {
			logx.Warn("writing the local API token failed; the tray cannot connect err=%s", logx.Err(err))
		}
	} else if d.RequireDashboard {
		return errors.New("the dashboard is disabled in config.json (dashboard.enabled=false); the app needs its API")
	} else {
		logx.Warn("the dashboard is disabled in config.json (dashboard.enabled=false)")
	}
	d.applyRouting(d.config().Routing)
	go d.runRoutingUpdates()
	d.superviseEngine()
	if d.dashboard != nil {
		d.dashboard.close()
	}
	logx.Info("service stopped")
	return nil
}

// Shutdown stops the proxy engine and the dashboard and waits (bounded)
// for run to return.
func (d *Daemon) Shutdown() {
	d.stopOnce.Do(func() { close(d.stop) })
	select {
	case <-d.finished:
	case <-time.After(15 * time.Second):
		logx.Warn("service shutdown timed out")
	}
}

// superviseEngine keeps the proxy engine running: it starts the engine,
// waits for a restart request, and retries failed starts. An engine starts
// asleep and contacts Mozilla only when first used (sleep.go). While no
// network is connected (network.wait_for_network) it does not start and
// starts as soon as one connects.
func (d *Daemon) superviseEngine() {
	var connectedAt time.Time
	for {
		select {
		case <-d.stop:
			return
		default:
		}
		if d.isOff() {
			if !d.waitWhileOff() {
				return
			}
			continue
		}
		if d.mustWaitForNetwork() {
			if !d.waitForNetwork() {
				return
			}
			connectedAt = time.Now()
			continue
		}
		d.setState(PhaseStarting, "Starting the proxy", time.Time{})
		engine, err := d.startEngine()
		if err == nil {
			d.mu.Lock()
			d.engine = engine
			// The public IP is found again once the new engine connects.
			d.exit = nil
			d.mu.Unlock()
			d.setState(PhaseRunning, "Proxy running", time.Time{})
			engineStopped := make(chan struct{})
			go d.sleepWhenIdle(engine, engineStopped)
			stopping := false
			select {
			case <-d.restart:
				logx.Info("restarting the proxy to apply changes")
			case <-d.stop:
				stopping = true
			}
			d.mu.Lock()
			d.engine = nil
			d.mu.Unlock()
			close(engineStopped)
			engine.stop()
			if stopping {
				return
			}
			continue
		}

		if d.mustWaitForNetwork() {
			// The network went away during the start; wait for it
			// rather than reporting the failure.
			continue
		}
		var wait time.Duration
		var noAccount *accounts.NoUsableAccountError
		var inUse *AddressInUseError
		switch {
		case errors.Is(err, errNoAccounts):
			d.setState(PhaseWaiting, "Add an account in the dashboard to start the proxy", time.Time{})
			wait = 24 * time.Hour
		case errors.As(err, &noAccount):
			wait = proxy.RenewalRetryDelay(err, time.Now())
			d.setState(PhaseWaiting, "No usable account: "+noAccount.Summary, time.Now().Add(wait))
			logx.Warn("no usable account; proxy waits wait=%s err=%s", wait, logx.Err(err))
		case errors.As(err, &inUse):
			// Retried like other errors, in case the other program lets
			// the port go; a new proxy.listen restarts at once.
			wait = engineStartRetry
			d.setStateCode(PhaseError, err.Error()+". Choose another SOCKS5 listen address in Settings", CodeProxyPortInUse, inUse.Address, time.Now().Add(wait))
			logx.Error("starting the proxy failed: its address is in use; retrying retry_in=%s listen=%s", wait, inUse.Address)
		default:
			wait = engineStartRetry
			if time.Since(connectedAt) < engineStartRetry {
				wait = networkSettleRetry
			}
			message := err.Error()
			if hint := proxy.GuardianFailureHint(err); hint != "" {
				message += ". " + hint
			}
			d.setState(PhaseError, message, time.Now().Add(wait))
			logx.Error("starting the proxy failed; retrying retry_in=%s err=%s", wait, logx.Err(err))
		}
		timer := time.NewTimer(wait)
		select {
		case <-timer.C:
		case <-d.restart:
			timer.Stop()
		case <-d.stop:
			timer.Stop()
			return
		}
	}
}

// mustWaitForNetwork: while no network is connected (no adapter with a
// default gateway; on Android, what the app reports), the proxy start
// waits instead of retrying Mozilla.
func (d *Daemon) mustWaitForNetwork() bool {
	return !networkConnected()
}

// waitForNetwork shows the wait and returns once a network connects or a
// restart is requested (a settings change may turn the wait off); false
// means the service stops.
func (d *Daemon) waitForNetwork() bool {
	d.setState(PhaseWaiting, MessageWaitingForNetwork, time.Time{})
	logx.Info("no network connected; the proxy starts when one connects")
	ticker := time.NewTicker(networkPoll)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			if !d.mustWaitForNetwork() {
				logx.Info("network connected; starting the proxy")
				return true
			}
		case <-d.restart:
			return true
		case <-d.stop:
			return false
		}
	}
}

// SetOn turns the proxy on or off while the daemon and its API keep
// running: off stops the engine, closing the proxy's port, and nothing
// connects to Mozilla until it is turned on again. The phone app uses it;
// it is not stored.
func (d *Daemon) SetOn(on bool) {
	d.mu.Lock()
	changed := d.off == on
	d.off = !on
	d.mu.Unlock()
	if changed {
		logx.Info("proxy turned on=%t", on)
		d.RequestRestart()
	}
}

// ProxyEndpoint is where clients in this process reach the proxy: its
// address on loopback (for a listen address on every interface) and its
// login. The phone's VPN mode sends its connections there.
func (d *Daemon) ProxyEndpoint() (addr, user, password string) {
	cfg := d.config()
	addr = cfg.Proxy.Listen
	if host, port, err := net.SplitHostPort(addr); err == nil {
		if ip := net.ParseIP(host); host == "" || (ip != nil && ip.IsUnspecified()) {
			addr = net.JoinHostPort("127.0.0.1", port)
		}
	}
	return addr, cfg.Proxy.Username, cfg.Proxy.Password
}

// NetworkChanged takes the phone's network state from Android: up after a
// change (another network, or one back), a connected proxy opens a new
// upstream session at once; down, the proxy waits for a network
// (network.wait_for_network). Either way the last connection test no longer
// says anything about the connection (StatusView.NetworkChangedAt).
func (d *Daemon) NetworkChanged(up bool) {
	netstate.Report(up)
	d.mu.Lock()
	d.networkChangedAt = time.Now()
	d.mu.Unlock()
	logx.Info("network changed connected=%t", up)
	if !up {
		return
	}
	engine := d.currentEngine()
	if engine == nil {
		d.RequestRestart() // a start waiting for the network goes on
		return
	}
	controller := engine.currentController()
	if controller == nil {
		return // asleep: the next connection connects on the new network
	}
	go func() {
		if err := controller.Reconnect(); err != nil {
			logx.Warn("reconnecting to Mozilla after a network change failed err=%s", logx.Err(err))
			return
		}
		logx.Info("reconnected to Mozilla on the new network")
		d.autoTest(engine, "network changed")
	}()
}

// ExitCountry is the country code the traffic leaves from: the selected
// location's, or for the recommended location (which has no country of
// its own) the exit's once a test or exit check found it; "" while it is
// unknown or the proxy is off. The phone's notification shows it.
func (d *Daemon) ExitCountry() string {
	engine := d.currentEngine()
	if engine == nil {
		return ""
	}
	selected, _ := engine.selection()
	if code := strings.ToUpper(selected.CountryCode); len(code) == 2 {
		return code
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.exit != nil && len(d.exit.CountryCode) == 2 {
		return strings.ToUpper(d.exit.CountryCode)
	}
	return ""
}

// Speed is the proxy's current speed in bytes per second (a few seconds'
// average); 0 while it is off.
func (d *Daemon) Speed() (down, up int64) {
	engine := d.currentEngine()
	if engine == nil || engine.routed == nil {
		return 0, 0
	}
	t := engine.routed.Traffic()
	return t.DownRate, t.UpRate
}

// Off makes Run start with the proxy off; call it before Run.
func (d *Daemon) Off() {
	d.mu.Lock()
	d.off = true
	d.mu.Unlock()
}

func (d *Daemon) isOff() bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.off
}

// waitWhileOff shows the off state until SetOn or a restart request; false
// means the service stops.
func (d *Daemon) waitWhileOff() bool {
	d.setState(PhaseOff, "Proxy off", time.Time{})
	select {
	case <-d.restart:
		return true
	case <-d.stop:
		return false
	}
}

// RequestRestart asks the supervisor to (re)start the proxy engine.
func (d *Daemon) RequestRestart() {
	select {
	case d.restart <- struct{}{}:
	default:
	}
}

func (d *Daemon) setState(phase, message string, retryAt time.Time) {
	d.setStateCode(phase, message, "", "", retryAt)
}

// setStateCode sets the state with a machine-readable problem code and the
// address it concerns.
func (d *Daemon) setStateCode(phase, message, code, address string, retryAt time.Time) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.state.Phase != phase || d.state.Message != message {
		d.state.Since = time.Now()
	}
	d.state.Phase, d.state.Message, d.state.RetryAt = phase, message, retryAt
	d.state.Code, d.state.Address = code, address
}

func (d *Daemon) config() config.Config {
	d.mu.Lock()
	defer d.mu.Unlock()
	cfg := d.cfg
	cfg.Accounts.Order = append([]config.AccountRef(nil), d.cfg.Accounts.Order...)
	return cfg
}

func (d *Daemon) currentEngine() *proxyEngine {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.engine
}

// accountsChanged reconciles the configured order with the store, reloads
// the account manager, and makes the engine pick up the change: a stopped
// engine is started, and a running one switches away from an account that
// was removed or disabled.
func (d *Daemon) accountsChanged() error {
	list, err := d.store.List()
	if err != nil {
		return err
	}
	d.mu.Lock()
	enabled, changed := ReconcileAccountOrder(&d.cfg, list)
	cfg := d.cfg
	d.mu.Unlock()
	if changed {
		if err := config.Save(d.paths.Config, cfg); err != nil {
			return fmt.Errorf("saving account order: %w", err)
		}
	}
	if err := d.mgr.Reload(enabled); err != nil {
		return err
	}
	engine := d.currentEngine()
	if engine == nil {
		d.RequestRestart()
		return nil
	}
	if _, ok := d.mgr.Active(); !ok {
		go d.switchAccount(engine)
	}
	return nil
}

// switchAccount obtains a pass from the account the manager now prefers and
// applies it to the running upstream session.
func (d *Daemon) switchAccount(engine *proxyEngine) {
	controller := engine.currentController()
	if controller == nil {
		// Asleep: the next wake takes a pass from the preferred account.
		return
	}
	if err := controller.SwitchAccountNow(); err != nil {
		logx.Warn("switching account failed: %s", logx.Err(err))
		if errors.Is(err, accounts.ErrNoUsableAccount) || errors.Is(err, proxy.ErrNoUsableSession) {
			d.RequestRestart()
		}
	}
}

// addSignedInAccount stores credentials issued by a sign-in and puts the
// account into rotation.
func (d *Daemon) addSignedInAccount(email, password string, token *fxa.TokenResponse) (accounts.Account, error) {
	now := time.Now()
	acc, created, err := d.store.Add(email, &fxa.SavedTokens{
		AccessToken:  token.AccessToken,
		RefreshToken: token.RefreshToken,
		Scope:        token.Scope,
		ObtainedAt:   now,
		ExpiresIn:    token.ExpiresIn,
	}, now)
	if err != nil {
		return accounts.Account{}, err
	}
	d.pool.Forget(acc.ID)
	if password != "" {
		if err := d.store.SetPassword(acc.ID, password); err != nil {
			logx.Warn("saving the account password failed account=%s err=%s", acc.Name(), logx.Err(err))
		}
	}
	go d.pool.EnsureDevice(context.Background(), acc.ID)
	if created {
		logx.Info("account added account=%s id=%s", acc.Name(), acc.ID)
	} else {
		logx.Info("account signed in again account=%s id=%s", acc.Name(), acc.ID)
	}
	if err := d.accountsChanged(); err != nil {
		return acc, err
	}
	if err := d.refreshAccountUsage(acc.ID); err != nil {
		logx.Debug("reading the new account's quota failed account=%s err=%s", acc.Name(), logx.Err(err))
	}
	return acc, nil
}

// removeAccount deletes an account and its credentials.
func (d *Daemon) removeAccount(id string) error {
	if _, err := d.store.Get(id); err != nil {
		return fmt.Errorf("unknown account %s", id)
	}
	if err := d.store.Remove(id); err != nil {
		return err
	}
	d.pool.Forget(id)
	logx.Info("account removed id=%s", id)
	return d.accountsChanged()
}

// setAccountOrder replaces the priority order; ids must name exactly the
// stored accounts.
func (d *Daemon) setAccountOrder(ids []string) error {
	d.mu.Lock()
	current := make(map[string]config.AccountRef, len(d.cfg.Accounts.Order))
	for _, ref := range d.cfg.Accounts.Order {
		current[ref.ID] = ref
	}
	if len(ids) != len(current) {
		d.mu.Unlock()
		return errors.New("the order must list every account exactly once")
	}
	order := make([]config.AccountRef, 0, len(ids))
	seen := make(map[string]bool, len(ids))
	for _, id := range ids {
		ref, ok := current[id]
		if !ok || seen[id] {
			d.mu.Unlock()
			return errors.New("the order must list every account exactly once")
		}
		seen[id] = true
		order = append(order, ref)
	}
	d.cfg.Accounts.Order = order
	d.mu.Unlock()
	return d.accountsChanged()
}

// setAccountEnabled takes an account in or out of rotation.
func (d *Daemon) setAccountEnabled(id string, enabled bool) error {
	d.mu.Lock()
	found := false
	for i := range d.cfg.Accounts.Order {
		if d.cfg.Accounts.Order[i].ID == id {
			d.cfg.Accounts.Order[i].Enabled = enabled
			found = true
		}
	}
	d.mu.Unlock()
	if !found {
		return fmt.Errorf("unknown account %s", id)
	}
	if err := d.saveConfig(); err != nil {
		return err
	}
	return d.accountsChanged()
}

// activateAccount makes id the active account now, switching the running
// engine to it.
func (d *Daemon) activateAccount(id string) error {
	enabled := false
	for _, acc := range d.mgr.Accounts() {
		if acc.ID == id {
			enabled = true
		}
	}
	if !enabled {
		return errors.New("only enabled accounts can be activated")
	}
	if err := d.mgr.Activate(id); err != nil {
		return err
	}
	logx.Info("account activated from the dashboard id=%s", id)
	if engine := d.currentEngine(); engine != nil {
		go d.switchAccount(engine)
	} else {
		d.RequestRestart()
	}
	return nil
}

// refreshAccountUsage reads an account's quota without minting a pass.
func (d *Daemon) refreshAccountUsage(id string) error {
	acc, err := d.store.Get(id)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), proxy.PassRenewTimeout)
	defer cancel()
	auth, err := d.pool.AuthFor(acc)
	if err != nil {
		return err
	}
	if auth, err = proxy.FreshRuntimeAuth(ctx, auth); err != nil {
		return err
	}
	usage, err := guardian.FetchProxyUsage(ctx, d.config().Network.GuardianEndpoint, auth.Token.AccessToken)
	if err != nil {
		return err
	}
	if _, err := d.mgr.ObserveUsage(id, proxy.AccountUsage(usage)); err == nil {
		return nil
	}
	// Disabled accounts are not managed; record the usage directly.
	u := proxy.AccountUsage(usage)
	acc.Usage = &u
	return d.store.Save(acc)
}

func (d *Daemon) saveConfig() error {
	return config.Save(d.paths.Config, d.config())
}

// settingsChange describes what an accepted settings update requires.
type settingsChange struct {
	restartEngine    bool
	restartDashboard bool
}

// updateSettings validates and saves a new configuration, applies what can
// change live, and reports what needs a restart. The account order is not
// changed here.
func (d *Daemon) updateSettings(next config.Config, newPassword *string) (settingsChange, error) {
	d.mu.Lock()
	prev := d.cfg
	d.mu.Unlock()

	next.Version = config.CurrentVersion
	next.Accounts.Order = prev.Accounts.Order
	next.Dashboard.Enabled = prev.Dashboard.Enabled
	next.Dashboard.Username = strings.TrimSpace(next.Dashboard.Username)
	switch {
	case next.Dashboard.Username == "":
		next.Dashboard.PasswordHash = ""
	case newPassword != nil && *newPassword != "":
		hash, err := HashDashboardPassword(*newPassword)
		if err != nil {
			return settingsChange{}, err
		}
		next.Dashboard.PasswordHash = hash
	case prev.Dashboard.PasswordHash != "":
		next.Dashboard.PasswordHash = prev.Dashboard.PasswordHash
	default:
		return settingsChange{}, errors.New("set a password for the dashboard username")
	}
	// Another region: its preset rules replace the old region's in the
	// Direct list; the user's own rules stay.
	if next.Routing.Region != prev.Routing.Region {
		next.Routing.Direct = routing.SwapRegionRules(prev.Routing.Region, next.Routing.Region, next.Routing.Direct)
		// One of the offered list sets follows the region (its usual one);
		// lists set by hand stay.
		if _, offered := routing.SourceOf(next.Routing.GeoSiteURL, next.Routing.GeoIPURL); offered {
			src := routing.RegionSource(next.Routing.Region)
			next.Routing.GeoSiteURL, next.Routing.GeoIPURL = src.GeoSiteURL, src.GeoIPURL
		}
	}
	if err := next.Validate(); err != nil {
		return settingsChange{}, err
	}
	if !slices.Equal(next.DNS.Servers, prev.DNS.Servers) || next.DNS.FallbackToSystem != prev.DNS.FallbackToSystem {
		if err := configureDNS(next.DNS); err != nil {
			return settingsChange{}, fmt.Errorf("invalid dns.servers: %w", err)
		}
	}
	if next.Network.APIRelay != prev.Network.APIRelay {
		if err := configureAPIRelay(next.Network.APIRelay); err != nil {
			return settingsChange{}, fmt.Errorf("invalid network.api_relay: %w", err)
		}
	}
	if err := config.Save(d.paths.Config, next); err != nil {
		return settingsChange{}, err
	}
	d.mu.Lock()
	d.cfg = next
	d.mu.Unlock()

	logx.Verbose.Store(next.Logging.Verbose || d.forceVerbose)
	proxy.AllowLockedLocations.Store(next.Proxy.AllowLocked)
	d.mgr.SetPolicy(accounts.Policy{ThresholdPercent: next.Accounts.SwitchThresholdPercent})
	change := settingsChange{
		restartEngine: next.Proxy != prev.Proxy || next.Network.APIRelay != prev.Network.APIRelay ||
			next.Network.GuardianEndpoint != prev.Network.GuardianEndpoint ||
			next.Accounts.QuotaCheckInterval != prev.Accounts.QuotaCheckInterval,
		restartDashboard: next.Dashboard.Listen != prev.Dashboard.Listen,
	}
	logx.Info("settings saved restart_proxy=%v restart_dashboard=%v", change.restartEngine, change.restartDashboard)
	if routingChanged(next.Routing, prev.Routing) {
		// Applied live: new connections take the new route.
		d.applyRouting(next.Routing)
		d.wakeRouting()
	}
	if change.restartEngine {
		if next.Proxy.Country != prev.Proxy.Country || next.Proxy.Server != prev.Proxy.Server {
			// A new location must not reuse the persisted hostname.
			_ = removeFile(d.paths.Selection)
		}
		d.RequestRestart()
	}
	return change, nil
}

// dashboardExposedWithoutLogin reports a dashboard reachable from other
// devices without credentials.
func dashboardExposedWithoutLogin(cfg config.Config) bool {
	if cfg.Dashboard.Username != "" {
		return false
	}
	host, _, err := net.SplitHostPort(cfg.Dashboard.Listen)
	if err != nil {
		return false
	}
	if host == "localhost" {
		return false
	}
	ip := net.ParseIP(host)
	return ip == nil || !ip.IsLoopback()
}
