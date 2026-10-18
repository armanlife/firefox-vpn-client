package proxy

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"sync/atomic"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/resolver"
	"github.com/armanlife/firefox-vpn-client/core/internal/routing"
)

// ErrBlockedByRule is a connection refused by a routing rule.
var ErrBlockedByRule = errors.New("refused by a routing rule")

// directDialTimeout bounds a direct connection.
const directDialTimeout = 15 * time.Second

// RouteCounts counts connections by route since the proxy started.
type RouteCounts struct {
	Proxy   int64 `json:"proxy"`
	Direct  int64 `json:"direct"`
	Blocked int64 `json:"blocked"`
}

// RoutedOpener opens each tunnel through Mozilla's proxy, directly through
// the local network, or not at all, as its router decides. Without a
// router everything goes through the proxy. The router can be replaced
// while connections are open.
type RoutedOpener struct {
	upstream tunnelOpener
	router   atomic.Pointer[routing.Router]
	// dial connects directly; tests replace it.
	dial func(ctx context.Context, network, address string) (net.Conn, error)
	// lookup resolves names for the router's IP rules (routing
	// resolve_domains) through Mozilla; tests replace it.
	lookup                   routing.LookupFunc
	proxied, direct, blocked atomic.Int64
	meter                    *trafficMeter
}

// directDialer opens the connections routed directly with the local
// network's own DNS, not dns.servers: they go to the local country's
// sites, whose names its DNS answers best (with the nearest servers), and a
// filtering DNS only hijacks foreign names.
var directDialer = &net.Dialer{}

// NewRoutedOpener routes the tunnels of upstream; Close stops its speed
// sampling.
func NewRoutedOpener(upstream tunnelOpener) *RoutedOpener {
	o := &RoutedOpener{upstream: upstream, dial: directDialer.DialContext, meter: newTrafficMeter()}
	// Names are looked up with DNS over HTTPS inside tunnels through
	// Mozilla: the local network's DNS may be filtered and answer a
	// blocked name with its block page's address (10.10.34.35 in Iran),
	// which IP rules such as geoip:private would then send directly.
	// These tunnels are not counted as client connections.
	names := resolver.NewThrough(func(_ context.Context, _, address string) (net.Conn, error) {
		return upstream.OpenTunnel(address)
	})
	o.lookup = func(ctx context.Context, host string) ([]netip.Addr, error) {
		result, err := names.Lookup(ctx, host)
		return result.Addrs, err
	}
	return o
}

// Lookup resolves host the way the router's IP rules see it: through
// Mozilla.
func (o *RoutedOpener) Lookup(ctx context.Context, host string) ([]netip.Addr, error) {
	return o.lookup(ctx, host)
}

// Close stops measuring the speed.
func (o *RoutedOpener) Close() { o.meter.close() }

// Traffic returns the bytes and speed so far.
func (o *RoutedOpener) Traffic() Traffic { return o.meter.traffic() }

// SetRouter installs r; nil sends everything through the proxy.
func (o *RoutedOpener) SetRouter(r *routing.Router) { o.router.Store(r) }

// Counts returns the connections by route so far.
func (o *RoutedOpener) Counts() RouteCounts {
	return RouteCounts{Proxy: o.proxied.Load(), Direct: o.direct.Load(), Blocked: o.blocked.Load()}
}

func (o *RoutedOpener) OpenTunnel(authority string) (net.Conn, error) {
	return o.OpenTunnelForClient(authority, "")
}

// OpenTunnelForClient keeps the client affinity of the upstream pool.
func (o *RoutedOpener) OpenTunnelForClient(authority, clientKey string) (net.Conn, error) {
	if r := o.router.Load(); r != nil {
		host, _, err := net.SplitHostPort(authority)
		if err == nil {
			switch r.Decide(context.Background(), host, o.lookup) {
			case routing.Direct:
				o.direct.Add(1)
				logx.Debug("route direct target=%s", logx.Target(authority))
				ctx, cancel := context.WithTimeout(context.Background(), directDialTimeout)
				defer cancel()
				conn, err := o.dial(ctx, "tcp", authority)
				if err != nil {
					return nil, err
				}
				return countConn(conn, &o.meter.directUp, &o.meter.directDown), nil
			case routing.Block:
				o.blocked.Add(1)
				logx.Debug("route blocked target=%s", logx.Target(authority))
				return nil, ErrBlockedByRule
			}
		}
	}
	o.proxied.Add(1)
	var conn net.Conn
	var err error
	if affinity, ok := o.upstream.(clientAffinityTunnelOpener); ok && clientKey != "" {
		conn, err = affinity.OpenTunnelForClient(authority, clientKey)
	} else {
		conn, err = o.upstream.OpenTunnel(authority)
	}
	if err != nil {
		return nil, err
	}
	return countConn(conn, &o.meter.up, &o.meter.down), nil
}
