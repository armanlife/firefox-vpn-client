package proxy

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"sync"
	"sync/atomic"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/guardian"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
)

const maxOpenTunnelRebuildRetries = 3

type managedSession struct {
	session   proxySession
	rawToken  string
	expiresAt time.Time
	refs      int
	accepting bool
}

type ControllerConfig struct {
	Guardian   string
	ProxyURL   *url.URL
	Timeout    time.Duration
	Auth       *runtimeAuth
	Pass       *guardian.ProxyPassInfo
	UseH3      bool
	Sessions   int
	StatusFile string
	Accounts   *AccountPool // optional; multi-account mode with threshold failover
}

type Controller struct {
	// OnSessionRebuilt, when set, runs after a failed upstream session was
	// replaced by a new one.
	OnSessionRebuilt func()

	guardian string
	proxyURL *url.URL
	timeout  time.Duration

	sessionFactory func(token string) (proxySession, error)
	refreshSession func() error
	accounts       *AccountPool

	// trafficSinceCheck counts tunnel bytes since the last quota check;
	// crossing usageProbeBytes requests an early check on quotaCheckNow.
	trafficSinceCheck atomic.Int64
	quotaCheckNow     chan struct{}

	renewMu    sync.Mutex
	mu         sync.Mutex
	auth       *runtimeAuth
	current    *managedSession
	statusFile string
	closed     bool
	done       chan struct{}

	// Guarded by mu: the latest quota state and the outcome of the last
	// renewal, reported in the status file without any secret.
	usage         *guardian.ProxyUsage
	lastError     string
	nextAttemptAt time.Time
	lastRenewalAt time.Time

	// Guarded by renewMu: rate limiting of tunnel-triggered rebuilds.
	lastRebuildAt  time.Time
	lastRebuildErr error

	closeOnce sync.Once
	closeErr  error
}

func NewController(cfg ControllerConfig) (*Controller, error) {
	var baseFactory func(token string) (proxySession, error)
	if cfg.UseH3 {
		baseFactory = func(token string) (proxySession, error) {
			return newH3ProxySession(cfg.ProxyURL, token, cfg.Timeout)
		}
	} else {
		baseFactory = func(token string) (proxySession, error) {
			return newH2ProxySession(cfg.ProxyURL, token, cfg.Timeout)
		}
	}
	sessions := cfg.Sessions
	if sessions < 1 {
		sessions = defaultUpstreamConnections
	}
	factory := func(token string) (proxySession, error) {
		if sessions == 1 {
			return baseFactory(token)
		}
		var tokenMu sync.RWMutex
		createToken := token
		return newProxySessionPool(sessions, func() (proxySession, error) {
			tokenMu.RLock()
			currentToken := createToken
			tokenMu.RUnlock()
			return baseFactory(currentToken)
		}, func(newToken string) {
			tokenMu.Lock()
			createToken = newToken
			tokenMu.Unlock()
		})
	}

	session, err := factory(cfg.Pass.RawToken)
	if err != nil {
		return nil, err
	}

	controller := &Controller{
		guardian:       cfg.Guardian,
		proxyURL:       cfg.ProxyURL,
		timeout:        cfg.Timeout,
		sessionFactory: factory,
		auth:           cfg.Auth,
		statusFile:     cfg.StatusFile,
		accounts:       cfg.Accounts,
		quotaCheckNow:  make(chan struct{}, 1),
		done:           make(chan struct{}),
		usage:          cfg.Pass.Usage,
		current: &managedSession{
			session:   session,
			rawToken:  cfg.Pass.RawToken,
			expiresAt: cfg.Pass.ExpiresAt(),
			accepting: true,
		},
	}
	controller.writeStatus("startup")
	return controller, nil
}

func (c *Controller) OpenTunnel(authority string) (net.Conn, error) {
	return c.openTunnel(authority, "")
}

func (c *Controller) OpenTunnelForClient(authority, clientKey string) (net.Conn, error) {
	return c.openTunnel(authority, clientKey)
}

func (c *Controller) openTunnel(authority, clientKey string) (net.Conn, error) {
	var lastErr error
	for attempt := 0; attempt <= maxOpenTunnelRebuildRetries; attempt++ {
		var failedSession *managedSession
		ms, release, err := c.acquireSession()
		if err != nil {
			if c.isClosed() {
				return nil, err
			}
			if !errors.Is(err, ErrNoUsableSession) || lastErr == nil {
				lastErr = err
			}
		} else if !isSessionAlive(ms.session) {
			// The keepalive already saw this session die; rebuild it instead of
			// spending a request to rediscover that.
			lastErr = errProxySessionUnhealthy
			failedSession = ms
			c.markSessionUnusable(ms)
			release()
		} else {
			var conn net.Conn
			if affinitySession, ok := ms.session.(clientAffinityTunnelOpener); ok {
				conn, err = affinitySession.OpenTunnelForClient(authority, clientKey)
			} else {
				conn, err = ms.session.OpenTunnel(authority)
			}
			if err == nil {
				return &managedTunnelConn{
					Conn:    conn,
					release: release,
					traffic: c.noteTraffic,
				}, nil
			}
			if !shouldRebuildProxySession(err) {
				release()
				return nil, err
			}
			lastErr = err
			failedSession = ms
			c.markSessionUnusable(ms)
			release()
		}

		if attempt == maxOpenTunnelRebuildRetries {
			break
		}

		logx.Warn("upstream tunnel open failed; rebuilding proxy session attempt=%d max=%d err=%s", attempt+1, maxOpenTunnelRebuildRetries, logx.Err(lastErr))
		if err := c.rebuildSession(failedSession); err != nil {
			lastErr = fmt.Errorf("rebuilding upstream proxy session: %w", err)
		}
	}
	return nil, lastErr
}

func (c *Controller) isClosed() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.closed
}

func (c *Controller) acquireSession() (*managedSession, func(), error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.closed {
		return nil, nil, ErrNoUsableSession
	}
	if c.current == nil || !c.current.accepting {
		return nil, nil, ErrNoUsableSession
	}
	if time.Now().After(c.current.expiresAt) {
		c.current.accepting = false
		c.maybeCloseLocked(c.current)
		return nil, nil, ErrNoUsableSession
	}

	ms := c.current
	ms.refs++
	return ms, func() { c.releaseSession(ms) }, nil
}

func (c *Controller) releaseSession(ms *managedSession) {
	c.mu.Lock()
	defer c.mu.Unlock()
	ms.refs--
	c.maybeCloseLocked(ms)
}

func (c *Controller) markSessionUnusable(ms *managedSession) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if ms == nil || c.current != ms {
		return
	}
	ms.accepting = false
	c.maybeCloseLocked(ms)
}

func (c *Controller) maybeCloseLocked(ms *managedSession) {
	if ms == nil || ms.accepting || ms.refs > 0 || ms.session == nil {
		return
	}
	_ = ms.session.Close()
	ms.session = nil
}

func (c *Controller) swapSession(newSession proxySession, rawToken string, expiresAt time.Time) bool {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		_ = newSession.Close()
		return false
	}
	old := c.current
	c.current = &managedSession{
		session:   newSession,
		rawToken:  rawToken,
		expiresAt: expiresAt,
		accepting: true,
	}
	if old != nil {
		old.accepting = false
		c.maybeCloseLocked(old)
	}
	c.mu.Unlock()
	c.writeStatus("session_swapped")
	return true
}

func (c *Controller) disableExpiredSession(now time.Time) {
	c.mu.Lock()
	changed := false
	if c.current != nil && c.current.accepting && !now.Before(c.current.expiresAt) {
		c.current.accepting = false
		c.maybeCloseLocked(c.current)
		changed = true
	}
	c.mu.Unlock()
	if changed {
		c.writeStatus("expired")
	}
}

// Reconnect opens a new upstream session with the current pass and makes it
// current, closing the old one: after a network change the old session's
// connection belongs to a network that is gone, and finding that out
// request by request takes time. No new pass is needed.
func (c *Controller) Reconnect() error {
	c.mu.Lock()
	old := c.current
	if c.closed || old == nil || old.rawToken == "" || !time.Now().Before(old.expiresAt) {
		c.mu.Unlock()
		return ErrNoUsableSession
	}
	token, expiresAt := old.rawToken, old.expiresAt
	c.mu.Unlock()
	session, err := c.sessionFactory(token)
	if err != nil {
		return err
	}
	if !c.swapSession(session, token, expiresAt) {
		return ErrNoUsableSession
	}
	c.mu.Lock()
	if old.session != nil {
		_ = old.session.Close()
		old.session = nil
	}
	c.mu.Unlock()
	return nil
}

// CurrentToken returns the proxy pass of the current session.
func (c *Controller) CurrentToken() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.current == nil {
		return ""
	}
	return c.current.rawToken
}

func (c *Controller) currentExpiry() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.current == nil {
		return time.Time{}
	}
	return c.current.expiresAt
}

func (c *Controller) hasUsableSessionOtherThan(failedSession *managedSession, now time.Time) bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.closed || c.current == nil || !c.current.accepting {
		return false
	}
	if failedSession != nil && c.current == failedSession {
		return false
	}
	return now.Before(c.current.expiresAt)
}

func (c *Controller) updateCurrentSessionToken(token string, expiresAt time.Time) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed || c.current == nil || !c.current.accepting || !time.Now().Before(c.current.expiresAt) {
		return ErrNoUsableSession
	}
	updater, ok := c.current.session.(proxySessionTokenUpdater)
	if !ok {
		return fmt.Errorf("upstream session does not support token update")
	}
	if err := updater.UpdateToken(token); err != nil {
		return err
	}
	c.current.rawToken = token
	c.current.expiresAt = expiresAt
	return nil
}

func (c *Controller) Close() error {
	c.closeOnce.Do(func() {
		if c.done != nil {
			close(c.done)
		}

		c.mu.Lock()
		defer c.mu.Unlock()

		c.closed = true
		if c.current != nil {
			c.current.accepting = false
			if c.current.session != nil {
				c.closeErr = c.current.session.Close()
				c.current.session = nil
			}
		}
	})
	c.writeStatus("closed")
	return c.closeErr
}

// noteTraffic counts tunnel bytes and requests an early quota check after
// usageProbeBytes, so a heavy transfer cannot run far past the account
// switch threshold between periodic checks.
func (c *Controller) noteTraffic(n int) {
	if n <= 0 {
		return
	}
	if c.trafficSinceCheck.Add(int64(n)) < usageProbeBytes {
		return
	}
	c.trafficSinceCheck.Store(0)
	select {
	case c.quotaCheckNow <- struct{}{}:
	default:
	}
}

type managedTunnelConn struct {
	net.Conn
	release func()
	traffic func(int)
	once    sync.Once
}

func (c *managedTunnelConn) Read(p []byte) (int, error) {
	n, err := c.Conn.Read(p)
	if c.traffic != nil {
		c.traffic(n)
	}
	return n, err
}

func (c *managedTunnelConn) Write(p []byte) (int, error) {
	n, err := c.Conn.Write(p)
	if c.traffic != nil {
		c.traffic(n)
	}
	return n, err
}

func (c *managedTunnelConn) Close() error {
	var err error
	c.once.Do(func() {
		err = c.Conn.Close()
		if c.release != nil {
			c.release()
		}
	})
	return err
}

func (c *managedTunnelConn) CloseRead() error {
	if closeReader, ok := c.Conn.(interface{ CloseRead() error }); ok {
		return closeReader.CloseRead()
	}
	return nil
}

func (c *managedTunnelConn) CloseWrite() error {
	if closeWriter, ok := c.Conn.(interface{ CloseWrite() error }); ok {
		return closeWriter.CloseWrite()
	}
	return nil
}
