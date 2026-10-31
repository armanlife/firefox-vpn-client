package service

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"sync"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/resolver"
)

const (
	// echKeyMinTTL and echKeyMaxTTL bound how long a key from DNS is kept;
	// Cloudflare changes its keys every few hours and publishes them with a
	// five-minute TTL. A server that refuses a stale key sends the new one.
	echKeyMinTTL = time.Minute
	echKeyMaxTTL = time.Hour
	// echKeyRetry is how long a failed key lookup stands before the next
	// one, so that requests in "on" mode do not each wait for DNS; an
	// answer that the name has no key (a relay that is not on Cloudflare)
	// stands echKeyMaxTTL.
	echKeyRetry = time.Minute
)

// echDialer opens the TLS connections to the API relay with Encrypted
// Client Hello: the network sees the key's public name (for a Cloudflare
// relay, cloudflare-ech.com), not the relay's. In "on" mode a relay that
// cannot be reached with ECH is reached without it; in "require" mode it
// is not reached at all. The certificate is checked against the relay's
// name either way.
type echDialer struct {
	host    string // the relay's name, sent inside the encrypted hello
	require bool
	keyName string // whose HTTPS record has the key: the relay's or another
	fixed   []byte // a key from the settings instead of DNS

	dial   func(ctx context.Context, network, address string) (net.Conn, error)
	lookup func(ctx context.Context, host string) ([]byte, time.Duration, error)
	base   *tls.Config // tests add their certificate authority

	mu       sync.Mutex
	key      []byte
	expires  time.Time
	keyErr   error // the last failed lookup, until expires
	reported string
}

func newECHDialer(host string, n config.Network, dial func(context.Context, string, string) (net.Conn, error)) (*echDialer, error) {
	name, key, err := config.ParseECHSource(n.APIRelayECHConfig)
	if err != nil {
		return nil, err
	}
	if name == "" {
		name = host
	}
	return &echDialer{
		host:    host,
		require: n.APIRelayECH == config.RelayECHRequire,
		keyName: name,
		fixed:   key,
		dial:    dial,
		lookup:  resolver.LookupECH,
		base:    &tls.Config{},
	}, nil
}

// DialTLSContext is the relay transport's TLS dial.
func (e *echDialer) DialTLSContext(ctx context.Context, network, address string) (net.Conn, error) {
	key, err := e.currentKey(ctx)
	if err != nil {
		return e.withoutECH(ctx, network, address, err)
	}
	conn, err := e.handshake(ctx, network, address, key)
	var rejected *tls.ECHRejectionError
	if errors.As(err, &rejected) && len(rejected.RetryConfigList) > 0 {
		// A stale key: the server sent the current one, authenticated by
		// its public name's certificate.
		e.setKey(rejected.RetryConfigList, echKeyMaxTTL)
		conn, err = e.handshake(ctx, network, address, rejected.RetryConfigList)
	}
	if err == nil {
		e.report("with ECH", nil)
		return conn, nil
	}
	if errors.As(err, &rejected) {
		err = errors.New("the relay does not take ECH")
	}
	if ctx.Err() != nil {
		return nil, err
	}
	return e.withoutECH(ctx, network, address, fmt.Errorf("ECH handshake: %w", err))
}

func (e *echDialer) handshake(ctx context.Context, network, address string, key []byte) (*tls.Conn, error) {
	raw, err := e.dial(ctx, network, address)
	if err != nil {
		return nil, err
	}
	cfg := e.base.Clone()
	cfg.ServerName = e.host
	cfg.MinVersion = tls.VersionTLS13
	cfg.EncryptedClientHelloConfigList = key
	conn := tls.Client(raw, cfg)
	if err := conn.HandshakeContext(ctx); err != nil {
		_ = raw.Close()
		return nil, err
	}
	return conn, nil
}

// withoutECH connects without ECH in "on" mode, and refuses in "require"
// mode.
func (e *echDialer) withoutECH(ctx context.Context, network, address string, why error) (net.Conn, error) {
	if e.require {
		e.report("refused", why)
		return nil, fmt.Errorf("no ECH (network.api_relay_ech is require): %w", why)
	}
	raw, err := e.dial(ctx, network, address)
	if err != nil {
		return nil, err
	}
	cfg := e.base.Clone()
	cfg.ServerName = e.host
	cfg.MinVersion = tls.VersionTLS12
	conn := tls.Client(raw, cfg)
	if err := conn.HandshakeContext(ctx); err != nil {
		_ = raw.Close()
		return nil, err
	}
	e.report("without ECH", why)
	return conn, nil
}

// currentKey returns the fixed key, the one kept from DNS, or a new one.
func (e *echDialer) currentKey(ctx context.Context) ([]byte, error) {
	if e.fixed != nil {
		e.mu.Lock()
		defer e.mu.Unlock()
		if e.key == nil {
			return e.fixed, nil
		}
		return e.key, nil
	}
	e.mu.Lock()
	if time.Now().Before(e.expires) {
		key, err := e.key, e.keyErr
		e.mu.Unlock()
		return key, err
	}
	e.mu.Unlock()

	key, ttl, err := e.lookup(ctx, e.keyName)
	e.mu.Lock()
	defer e.mu.Unlock()
	if err != nil {
		if ctx.Err() == nil {
			wait := echKeyRetry
			if errors.Is(err, resolver.ErrNoECH) {
				wait = echKeyMaxTTL
			}
			e.key, e.keyErr, e.expires = nil, err, time.Now().Add(wait)
		}
		return nil, err
	}
	e.key, e.keyErr, e.expires = key, nil, time.Now().Add(min(echKeyMaxTTL, max(echKeyMinTTL, ttl)))
	return key, nil
}

func (e *echDialer) setKey(key []byte, ttl time.Duration) {
	e.mu.Lock()
	e.key, e.keyErr, e.expires = key, nil, time.Now().Add(ttl)
	e.mu.Unlock()
}

// report logs how the relay is reached when that changes.
func (e *echDialer) report(how string, why error) {
	e.mu.Lock()
	changed := e.reported != how
	e.reported = how
	e.mu.Unlock()
	if !changed {
		return
	}
	switch how {
	case "with ECH":
		logx.Info("API relay %s reached with ECH (its name is hidden)", e.host)
	default:
		logx.Warn("API relay %s %s err=%s", e.host, how, logx.Err(why))
	}
}
