package service

import (
	"context"
	"sync"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/netcheck"
	"github.com/armanlife/firefox-vpn-client/core/internal/netstate"
	"github.com/armanlife/firefox-vpn-client/core/internal/proxy"
	"github.com/armanlife/firefox-vpn-client/core/internal/resolver"
)

// failureCode is proxy.FailureCode for err, made sure for failures that may
// be this device's own: no route or name (no_network), no answer
// (unreachable), or anything unknown (other). The internet is then checked
// outside the tunnel (netcheck), every time, since the network may have
// changed: without it the code is no_network; with it, a Mozilla name that
// does not resolve or a route that does not exist means a network that
// filters Mozilla (unreachable), or, when the internet itself leaves
// through a VPN's exit, a VPN that lets only web ports through
// (inside_vpn). A phone that reported no network needs no check, nor does a
// way through the user's own proxy (upstream_proxy): the internet outside it
// says nothing about it.
func failureCode(err error) string {
	return checkedFailure(proxy.FailureCode(err))
}

func checkedFailure(code string) string {
	switch code {
	case proxy.FailureNoNetwork, proxy.FailureUnreachable, proxy.FailureOther:
	default:
		return code
	}
	if netstate.ReportedDown() {
		return proxy.FailureNoNetwork
	}
	if resolver.UpstreamProxy() != "" {
		return proxy.FailureUpstreamProxy
	}
	switch netcheck.Check(context.Background()) {
	case netcheck.Offline:
		return proxy.FailureNoNetwork
	case netcheck.Online:
		if code == proxy.FailureNoNetwork {
			code = proxy.FailureUnreachable
		}
		if code == proxy.FailureUnreachable && insideVPN() {
			return proxy.FailureInsideVPN
		}
	}
	return code
}

// insideVPNTTL is how long a network's answer stands: it is asked once
// for a failing network, not at every retry.
const insideVPNTTL = 10 * time.Minute

var insideVPNSeen struct {
	sync.Mutex
	network string
	at      time.Time
	inside  bool
}

// insideVPN is netcheck.InsideVPN, kept for the current network.
func insideVPN() bool {
	network, _ := networkNow()
	s := &insideVPNSeen
	s.Lock()
	if !s.at.IsZero() && s.network == network && time.Since(s.at) < insideVPNTTL {
		inside := s.inside
		s.Unlock()
		return inside
	}
	s.Unlock()
	inside := netcheck.InsideVPN(context.Background())
	s.Lock()
	s.network, s.at, s.inside = network, time.Now(), inside
	s.Unlock()
	return inside
}
