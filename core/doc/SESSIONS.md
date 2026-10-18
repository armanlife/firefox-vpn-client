# Sessions, Transports, and Concurrency

The relevant implementation is in [cmd/firefox-vpn-core](../cmd/firefox-vpn-core): `controller.go`, `renewal.go`, `pool.go`, `session.go`, `tunnel.go`, `upstream_h2.go`, `upstream_h3.go`, `socks.go`, and `relay.go`. Read [authentication](AUTHENTICATION.md) for pass acquisition and [testing](TESTING.md) for regression cases.

## Ownership and admission

`Controller.current` (`internal/proxy`) points to a `managedSession` containing the session, raw bearer token, expiry, reference count, and admission flag.

1. `acquireSession` checks controller state, admission, and expiry while holding `c.mu`, then increments references.
2. `openTunnel` delegates to the session/pool. Successful streams are wrapped in `managedTunnelConn`.
3. Closing the wrapper releases its controller reference exactly once.
4. `swapSession` installs a replacement, stops admission on the old managed session, and leaves existing references to drain.
5. `maybeCloseLocked` closes a non-accepting session only after references reach zero.

Normal renewal first attempts `updateCurrentSessionToken`. If the current session is usable and supports `UpdateToken`, it keeps its connection(s), updates bearer/expiry, and writes `reason=token_updated`. Existing CONNECT streams continue using their established stream.

If adoption cannot happen in place, `adoptPass` creates and swaps a replacement. `disableExpiredSession` rejects new work on an expired managed session without intentionally tearing down all referenced tunnels.

Do not generalize these admission rules to explicit controller shutdown. `Close` closes owned sessions; the CLI has no managed signal handler guaranteeing graceful drain on process termination.

## Synchronization map

This table identifies existing responsibilities. Inspect acquisition order at the affected call sites before changing locks.

| Synchronization | Guards / purpose |
| --- | --- |
| `Controller.renewMu` | Serializes renewal, rebuild, quota-check, and account-switch transactions |
| `Controller.mu` | Current managed session, auth pointer, admission, references, closed state |
| H2/H3 token mutexes | Bearer reads and `UpdateToken` writes |
| `proxySessionPool.mu` | Slot list, client affinity map, pool closed state |
| `proxySessionPool.tokenMu` | Latest token applied to replacement sessions |
| `pooledProxySession.mu` | Underlying slot session, health/retirement, slot references |
| `sessionFailureTracker.mu` | Distinct target-failure sets |
| `accounts.Manager.mu`, `AccountPool.mu` | Account statuses and active account; cached per-account credentials. Separate from upstream-session pooling |
| `service.Daemon.mu` | Config copy, running engine, engine state, last exit/test results |
| `sync.Once` in close paths | Avoids duplicate teardown or reference release |

The controller token-update path currently invokes the session updater while holding `c.mu`. Avoid introducing callbacks into controller state from an updater without analyzing lock interactions. Do not move network work into a critical section simply for convenience.

Renewal, dead-session rebuild, and quota polling can overlap. `rebuildSession` checks whether another usable session already replaced the failed one before repeating work.

## Upstream-session pool

`proxySessionPool` implements the session interface. It is distinct from the account pool (`AccountPool`), which chooses the Firefox Account that supplies the ProxyPass.

- Client IP determines a sticky slot; failover remembers a usable fallback. Calls without a client key use the pool's alternate selection path.
- Dead/broken slots are retired and replenished. Pool startup can succeed with a partial set of sessions if at least one was created.
- Old slot references drain before retirement closes the underlying session.
- Token updates must reach both existing slots and sessions created concurrently with renewal. `setCreateToken` and the latest-token path prevent replacements from retaining stale credentials.
- Multiple sessions do not establish a fixed exit IP or aggregate-bandwidth guarantee.

Relevant tests include `TestProxySessionPoolPinsClientToOneSession`, `TestProxySessionPoolKeepsClientOnFailoverSession`, `TestProxySessionPoolStartsWithPartialSuccess`, `TestProxySessionPoolReplenishesBrokenSession`, and both replacement-token update tests.

## Failure classification

`sessionFailureTracker.observe` tracks opening timeouts and HTTP 502 separately:

- Three distinct targets of the same tracked failure category mark the session unhealthy.
- A success clears tracked failures.
- Switching between timeout and 502 categories clears the other set.
- Repeating the same failing target does not accumulate distinct-target evidence.
- A 502 for a port other than 80, 443, 8080, or 8443 is Mozilla's proxy refusing the port (`portRefused`, `upstreamPorts`): it neither counts nor clears anything. Before this, a few requests to such ports retired a healthy session and, through the rebuild cooldown, stopped every connection for about a minute.

`shouldRebuildProxySession` then distinguishes authentication/session failures from ordinary destination errors:

| Observation | Current handling |
| --- | --- |
| HTTP 401, 403, 407 on CONNECT | Rebuild classification |
| HTTP 429 alone | No immediate rebuild classification |
| Other HTTP errors, including isolated 502 | No immediate rebuild unless wrapped as session unhealthy |
| Opening timeout alone | No immediate rebuild unless the failure tracker establishes session failure |
| Broken connection / explicit unhealthy state | Rebuild classification |

The controller permits up to `maxOpenTunnelRebuildRetries`, currently three rebuilds. Preserve bounded retries, the final error, and the check for a concurrently replaced session. Retrying cannot add a direct-target fallback.

Rebuilds that fetch a new pass are rate limited: within `sessionRebuildCooldown` (10 seconds) of the previous rebuild, `rebuildSession` returns `errRebuildCoolingDown` with the previous outcome instead of contacting Guardian again. This keeps a persistent CONNECT rejection (for example HTTP 403 on a location the account may not use) from turning every client request into Guardian round trips. Test hooks that set `refreshSession` bypass the cooldown.

## H2 and H3 transport contracts

| Property | H2 | H3 |
| --- | --- | --- |
| Network | TLS over TCP | QUIC over UDP |
| ALPN | `h2` | `h3` |
| TLS minimum | 1.2 | 1.3 |
| Stream operation | HTTP CONNECT over one multiplexed session | HTTP CONNECT over one multiplexed QUIC session |
| Token update | Mutex-protected bearer for future CONNECT requests | Same contract |
| Keepalive | Active 10-second PING, 5-second deadline | 30-second QUIC keepalive |

H2 transport also configures read-idle 30 seconds, PING timeout 15 seconds, and write-byte timeout 30 seconds. H3 sets initial packet size to 1200 bytes and tries resolved addresses with bounded attempts. Keep certificate-chain/hostname validation and protocol negotiation checks intact.

The live audit verified H2. Local H3 passed, while live H3 timed out; this does not establish a single cause for the timeout.

## SOCKS and stream forwarding

`SOCKSServer` handles TCP clients with a per-client handler and optional concurrency limit. Its handshake supports only the no-authentication method and CONNECT for IPv4, IPv6, or domain targets. Ensure handshake failures, rejected connections, and forwarding errors release the relevant resources and slots.

`proxyBidirectional` forwards in both directions. Abnormal copy errors close both sides. Normal half-close drains for at most `halfCloseDrainTimeout`, currently two minutes. Optional idle handling is separate from the initial SOCKS handshake and CONNECT opening timeout.

| Resource / timeout | Current contract |
| --- | --- |
| Copy buffer | 64 KiB pool |
| Tunnel write buffer | Bounded at 1 MiB |
| Client handshake timeout | Default 10 seconds; zero disables |
| Established idle timeout | Default zero; optional cutoff |
| Tunnel deadline methods | Explicitly return `errTunnelDeadline` |
| CONNECT opening timeout | Bounded opening operation, not stream lifetime |

A cancellation race can complete a connection after the caller stopped waiting. Preserve cleanup verified by `TestOpenTunnelContextClosesConnectionThatArrivesAfterCancellation`. Do not silently treat unsupported `net.Conn` deadline setters as successful.

## Lazy start and sleep

An engine (`internal/service`, `proxyEngine`) starts with no controller and builds one only when something needs Mozilla (`Daemon.useController`). `idleState.mu` guards the controller pointer, the use count, `sleeping`, `stopped`, the last wake failure, and the selected location; `idleState.wakeMu` serializes wakes and guards the engine's upstream configuration, so connections that arrive together wait for one wake and then all reserve the same controller. Wakes are network work and run outside `idleState.mu`. `runController` installs a new controller only while the engine is not stopped (`stopped`, set by `proxyEngine.stop` under the same lock); a wake that finishes after the stop closes its controller, so no renewal loop outlives its engine. Client connections do not repeat a failed wake for `wakeRetryCooldown`; the connection test and the real-delay test do.

## Before changing lifecycle code

Trace who owns the socket, who holds the controller reference, who holds the pool-slot reference, and which close path releases each one. Cover the overlap that motivates the change: token update during slot replacement, rebuild during renewal, or shutdown during a pending operation. Existing focused tests are mapped in [TESTING.md](TESTING.md); add a regression only for the changed failure mode.
