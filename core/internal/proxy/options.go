package proxy

import (
	"sync/atomic"
	"time"
)

const (
	defaultUpstreamConnections = 1

	// APIRequestTimeout bounds a single control plane API call (FxA,
	// Guardian, Remote Settings); the shared client adds its own safety
	// timeout on top, and FxA calls extend it while solving the Fastly
	// anti-bot challenge.
	APIRequestTimeout = 15 * time.Second
)

// AllowLockedLocations permits automatic selection of locked locations; the
// dashboard can change it at runtime.
var AllowLockedLocations atomic.Bool
