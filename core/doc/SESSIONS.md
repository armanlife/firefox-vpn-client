# Sessions, Transports, and Concurrency

The relevant implementation is in [cmd/arman-vpn-core](../cmd/arman-vpn-core): `controller.go`, `renewal.go`, `pool.go`, `session.go`, `tunnel.go`, `upstream_h2.go`, `upstream_h3.go`, `upstream_h1.go`, `socks.go`, and `relay.go`. Read [authentication](AUTHENTICATION.md) for pass acquisition.

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
| `ServerFailover.mu` | The failing server's count and the avoided servers; `Controller.mu` guards the controller's `server` and `proxyURL`, which the failover changes under `renewMu` |
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
- Git over SSH to GitHub (`github.com:22`) is sent through Mozilla to `ssh.github.com:443`, GitHub's SSH server on the HTTPS port, with the same protocol and host keys (`throughMozilla` in `route.go`); a direct route keeps port 22.
- Google's push server, which delivers the notifications of Android and Chrome (`mtalk.google.com` and `altN-mtalk.google.com` on 5228-5230 or 443, `pushServer`), is connected directly first (`openPush`, 5 seconds at most): its one long connection then neither waits for nor breaks with the session to Mozilla, and uses no quota. When it cannot be reached directly, it and the next ones go through Mozilla for 10 minutes, on port 443, where the same server speaks the same protocol. A routing rule for these names wins.
- A 502 for a port other than 80, 443, 8080, or 8443 is Mozilla's proxy refusing the port (`portRefused`, `upstreamPorts`): it neither counts nor clears anything. Before this, a few requests to such ports retired a healthy session and, through the rebuild cooldown, stopped every connection for about a minute.

`shouldRebuildProxySession` then distinguishes authentication/session failures from ordinary destination errors:

| Observation | Current handling |
| --- | --- |
| HTTP 401, 403, 407 on CONNECT | Rebuild with a new pass; a 403 or 407 on a session whose pass was fetched after a refusal goes back to the client (see below) |
| HTTP 429 alone | No immediate rebuild classification |
| Other HTTP errors, including isolated 502 | No immediate rebuild unless wrapped as session unhealthy |
| Opening timeout alone | No immediate rebuild unless the failure tracker establishes session failure |
| Broken connection / explicit unhealthy state | Rebuild by redialing with the current pass |

The controller permits up to `maxOpenTunnelRebuildRetries`, currently three rebuilds. Preserve bounded retries, the final error, and the check for a concurrently replaced session. Retrying cannot add a direct-target fallback.

A rebuild is one of two kinds (`rebuildNeedsPass`, `replaceSessionLocked`). A failure of the connection (a dead session, resets, timeouts, a run of 502s on distinct targets) redials with the current pass (`redialLocked`, as `Reconnect` does) while that pass is valid for more than the renewal lead; Guardian is not asked. A CONNECT 401, 403, or 407, or no session at all, fetches a new pass. Firefox fetches a pass only when one expires, so new passes are spaced: the first after a working tunnel waits at least 10 seconds after the previous one, and each further one in a row waits longer (10 s, 30 s, 1 min, then 2 min: no wait is longer than a user waits out); redials in a row wait 0, 10 s, 30 s, then 1 min (`rebuildBackoff`, `redialSteps`, `newPassSteps`). A tunnel that opens resets both. A rebuild that failed because the device had no network (`FailureNoNetwork`) is not counted, since it reached nothing at Mozilla. When the phone reports a network back (`Daemon.NetworkChanged`), or a computer's networks change (`Daemon.watchNetwork` reads them every 2 seconds through `netstate.Current`: on Windows the adapters that are up with a default gateway, their addresses and gateways; on Linux the default routes; nothing is sent, and macOS is not watched), `Controller.RetryNow` forgets both spacings and a renewal wait left by a network failure, and the daemon opens a new session on the new network (`Reconnect`), retrying after 1, 2, 4, and 8 seconds while the network settles (mobile data often reports before it routes anything), until a later network change or engine takes over (`reconnectOnNewNetwork`). Without this, a phone whose data was off for a moment kept the dead session of the old network and waited out minutes of backoff. While the phone reports no network, a tunnel failure rebuilds nothing and fails at once as `FailureNoNetwork` (`ErrNoNetwork`): Guardian requests then could only fail, retrying for seconds, and would finish when the network returns, building a second session in a race with the new network's `Reconnect`. A connection test that fails because its session was replaced while it ran (`SessionReplaced`) runs again at once on the session in place. While waiting, `rebuildSession` returns `errRebuildCoolingDown` wrapping the last failure (or its cause). A new pass also waits while the renewal loop waits after a failure (`nextAttemptAt`), so a spent quota or an account that must sign in again is not retried by client requests.

A pass fetched because Mozilla refused the previous one marks its session (`managedSession.afterRefusal`). A CONNECT 403 or 407 on that session is the location's or the destination's answer, not the pass's (`refusedAgain`): the client gets the refusal, the session stays in use for the others, and no further pass is fetched; a renewed pass clears the mark. When the user chose the location (`ControllerConfig.ChosenLocation`: a country, not the recommended location or `fastest`), the refusal is wrapped in `LocationRefusedError`, whose failure code is `location_refused`. Test hooks that set `refreshSession` bypass the spacing.

## Server failover

`ServerFailover` ([failover.go](../internal/proxy/failover.go)) moves the upstream to another server of the selected location when one server keeps failing. The daemon holds one (`Daemon.failover`) for its whole run, shared by the wakes and the controllers of every engine; a server set by hand (`proxy.server`) gets none and never moves.

- **What counts.** A failed attempt to open a session on the server: a redial or the session for a new pass (`dialSession`, from `redialLocked` and `adoptPass`), and a wake's `NewController` (`connectEngine`, `reconnectEngine`; after the HTTP/3 fallback, only the final error). When a redial works, the session it replaced counts instead if it broke on the server (dead, or unhealthy by the failure tracker). A rebuild counts once. `serverFault` leaves out what is not the server's fault: no network (`FailureNoNetwork`, including `ErrNoNetwork` while the phone reports none), the account or its pass (Guardian's answers, such as 401, 403, 429, or 5xx; `fxa.ErrReauthRequired`; no usable account; a CONNECT 401, 403, 407, or 429; `location_refused`), a cancelled context, and a rebuild that is cooling down or found no session. A 502 for a refused port never rebuilds, so it never counts. `Reconnect` after a network change does not count.
- **Reset.** A tunnel that opens on the server clears its count in a row (`Worked`, called with `managedSession.server`), not its recent failures.
- **Threshold.** Three failures in a row (`serverFailoverStrikes`), or four within five minutes (`serverDropLimit`, `serverDropWindow`) with tunnels opening between them: some networks cut the connection to a server every minute or so, so each new session works for a while and the count in a row never reaches three. With the rebuild spacing (redials 0, 10 s, 30 s; new passes 10 s apart and more), a dead server is left within about 10 to 40 seconds of its first failure, while one or two failures, as a short network blip causes, do not move it. The same thresholds apply to failed wakes.
- **Next server.** The failed server is avoided for 15 minutes (`serverAvoidTime`): long enough that the location's other servers are tried before it, short enough that a server back from an outage returns to the choice. `nextServer` picks another server of the same city at random, else one of the location's next city that has one, skipping avoided servers. The location is `LocationCandidates`: the chosen country's servers, the recommended location's (`REC`), or, for `fastest`, those of the country it resolved to, in server-list order. A chosen country never changes.
- **Stand-ins.** The recommended location has a single anycast server, so it has stand-ins (`ControllerConfig.Fallback`, `Daemon.recommendedFallback`): the servers of the country its traffic last left from (the exit check), then of the fastest locations last measured, then of `recommendedFallbackCountries` (NL, DE, BE, FR, GB, AT), three locations at most. When none of the location's own servers is left, `Failed` moves to the first stand-in that is not avoided, logs it (`using another location's server for now`), and does not save it: the recommended location accepts any persisted server and would keep it. The configured choice stays the recommended location. The next rebuild after the recommended server's avoidance ended goes back to it (`Controller.returnToLocation`, which does not count the stand-in's failure that brought the rebuild), and a first wake while it is avoided connects to a stand-in (`ServerFailover.Instead`).
- **Switch.** `Failed` logs the switch at INFO with `from` and `to` and saves the new server to `selection.json`, so a restart does not go back. The controller (`failOver`) points `server` and `proxyURL` at it, restarts the redial steps, and dials it at once; `OnServerSwitched` makes it the engine's selection (`selection_source` `server_failover` in the status), which the next wake after sleep connects to. A wake that switched lets the next wake try at once instead of waiting `wakeRetryAt`. A session pool stays on the server it was made for: its replacement slots belong to a session being drained.
- **Every server failed.** When every other server of the location is avoided, `Failed` logs a warning and the upstream stays where it is; the count starts again and the usual rebuild and wake spacing applies. A server whose avoidance ended is eligible again.
- **Selection.** A first wake passes `ServerFailover.Avoided` to `ResolveWithStateAndCountry`: an avoided persisted server is replaced, and `selectProxyCandidate` skips avoided servers unless the location has no other. When the first HTTP/2 connection to the automatic recommended server times out, the same wake tries one available stand-in with the same pass. If that connection succeeds, the recommended server is temporarily avoided and the stand-in is used without saving it as the preferred server. If neither connects, the ordinary wake retry policy applies.

Tests: `TestServerFailingThreeTimesSwitchesToAnotherServerOfItsCity`, `TestServerFailoverCountsTheDialsOfNewPasses`, `TestBrokenSessionsMoveTheServer`, `TestDroppingSessionsMoveTheServer`, `TestRecommendedLocationUsesAStandIn`, `TestFailuresThatAreNotTheServersDoNotSwitch`, `TestEveryServerFailingKeepsTheLocation`, `TestAvoidedServerIsSkippedUntilItsTimeIsUp`, `TestRecommendedLocationFailsOverWithinItself` (`internal/proxy`), `TestWakeMovesToAnotherServerOfTheLocation` and `TestRecommendedFallbackOrder` (`internal/service`).

## H2 and H3 transport contracts

| Property | H2 | H3 |
| --- | --- | --- |
| Network | TLS over TCP | QUIC over UDP |
| ALPN | `h2` | `h3` |
| TLS minimum | 1.2 | 1.3 |
| Stream operation | HTTP CONNECT over one multiplexed session | HTTP CONNECT over one multiplexed QUIC session |
| Token update | Mutex-protected bearer for future CONNECT requests | Same contract |
| Keepalive | Active 5-second PING, 5-second deadline, two misses | 30-second QUIC keepalive |

A tunnel's receive window is 1 MiB (`upstreamStreamWindow`), not Go's default 4 MiB. All tunnels share one connection, so the answer to a new tunnel comes behind everything the server has sent or queued on the others, and the window bounds that for a download: the larger it is, the longer a new connection waits beside a download, and a much smaller one lowers the speed. A separate connection to the same server is not delayed at the same time, so the queue belongs to the one connection, not the line. One tunnel's speed is at most the window per round trip. The connection's window stays large: a client that stopped reading holds on to its tunnel's share, and a small total would let a few of them stop every tunnel.

The H2 keepalive (`runKeepAlive`) counts a PING as missed only when no data arrived while it waited (`watchedConn`, the TCP connection under the TLS, notes the time of the last read): on a busy phone link a PING can wait behind a video's data. Nor does it count while an upload may be the reason (`watchedConn.uploading`: at least 256 KiB sent since data last arrived, for up to 45 seconds): the PING waits behind the upload in the link's queue, and nothing arrives meanwhile. After two misses in a row, or when the connection has closed, the session is dead: the keepalive logs one line (`reportConnectionLost`) and closes the connection, so the tunnels waiting on it fail at once and are retried on a new session instead of waiting out their CONNECT timeout. A connection the network stopped carrying is found within about 15 seconds. The line names the server, its IP, how long the connection lived, why it ended (`lossReason`, from the connection's first read or write error: `no answer from the network`, `cut off (reset)`, `closed by the other side`), and the tunnels it carried; from the third loss to one IP within 10 minutes, after under 3 minutes each on average, it says `the network keeps cutting the connection to this server` with `lost_in_10m` and `average_life`. Of the tunnels that fail together when a session dies, only the first logs `rebuilding proxy session` at WARN (`firstToReport`); the others log at DEBUG. Tests: `TestKeepAliveClosesAConnectionTheNetworkStoppedCarrying`, `TestWatchedConnNotesArrivingData`, `TestLossReason`, `TestRepeatedLossesShowTheNetworkCuttingTheConnection`.

H2 transport also configures read-idle 30 seconds, PING timeout 15 seconds, and write-byte timeout 30 seconds. H3 sets initial packet size to 1200 bytes and tries resolved addresses with bounded attempts. Keep certificate-chain/hostname validation and protocol negotiation checks intact.

HTTP/2 connections to Mozilla send the ClientHello of desktop Firefox (`firefoxHello` in `upstream_tls.go`: the same lists in the same order), so they look like the Firefox their User-Agent names. If that handshake fails, the connection is tried again with Go's own TLS, which then stays until the program restarts (`upstreamGoTLS`). HTTP/3 and the control plane use Go's TLS.

New TLS connections resume an earlier session (`upstreamTLSSessions`, `upstreamFirefoxSessions`, `upstreamH3TLSSessions`), which saves a whole handshake when the network cuts connections. The ClientHello goes out as `network.hello_split` says (`internal/hellosplit`, under the TLS of the sessions below and of the control plane's and the relay's connections): `off`, the default, sends it whole; `first-byte` cuts it after the first byte; `sni` cuts it after the first letter of the server's name; `record` makes two TLS records of it, cut at the same place, so TCP reassembly alone does not show the whole name. The user chooses; nothing moves between them by itself. The name stays the real one: Mozilla's proxy refuses any other.

The live audit verified H2. Local H3 passed, while live H3 timed out; this does not establish a single cause for the timeout.

## The local network

Mozilla's proxy cannot reach the local network, so an address of it (private, link-local, or this machine's) goes directly even with routing off or its lists not loaded (`proxy.LocalAddress`, `RoutedOpener.decide`), and on any port in the VPN (`TunnelAllows`). A Block rule still wins. UDP to the local network stays refused in the VPN (`TunnelAllowsUDP`). Only an address counts: a name goes where the routing sends it.

## UDP (CONNECT-UDP)

Mozilla's proxy carries UDP with CONNECT-UDP (RFC 9298) over HTTP/2: an extended CONNECT stream (RFC 8441) with `:protocol connect-udp`, the path `/.well-known/masque/udp/{host}/{port}/`, and `capsule-protocol: ?1`, each packet a DATAGRAM capsule (RFC 9297) with context ID 0. It connects to the UDP ports **80, 443, 3478, 8080, 8443, and 49152 to 65534**; others answer 502 with `Proxy-Status: Fastly; error=destination_ip_prohibited` (`udpPorts`; measured 2026-10-30).

| Part | File | Contract |
| --- | --- | --- |
| HTTP/2 client | `udp_h2.go` (`udpH2Conn`, `udpH2Stream`) | Its own small client on x/net's framer: under Go 1.27 `http2.Transport` hands over to `net/http`, which refuses `:protocol`. One `writeLoop` writes (HPACK needs one order) and one `readLoop` reads. |
| Connections | `udp.go` (`udpUpstream`, `Controller.OpenUDP`) | Separate from the TCP tunnels' session, so a download does not delay a call's packets; opened at the first UDP, to the current server; closed after a minute without streams, on `Reconnect`, and when the server changes. At most 8, each up to the server's stream limit. Always HTTP/2, also when TCP uses HTTP/3. |
| Routing | `udp.go` (`RoutedOpener.OpenUDP`) | The routing rules as for TCP; port 53 answered with DNS over HTTPS through Mozilla; a port Mozilla does not carry refused without asking it (`ErrUDPPort`). |
| Clients | `socks_udp.go` (`udpAssociation`, `udpFlow`) | SOCKS5 UDP ASSOCIATE. Each destination of a client's socket is a flow with a stream of its own; at most 128 (the one unused for longest goes); closed after 2 minutes without packets. Only the client's IP, and the port of its first packet, is served. |

A packet is never waited for. One the connection cannot take now (the flow-control window, or 256 KiB already queued) is dropped, as a full router would; so is one received while the client is behind (256 packets per stream). Keepalive: a PING every 5 seconds; a connection silent for 15 seconds is closed unless an upload explains it (`watchedConn.uploading`), and its flows open again with their next packets. A tunnel that failed is tried again after 2 seconds, a refused destination after 30.

UDP counts toward the account's quota and the traffic like TCP, and keeps the engine awake while a flow is open. A pass the proxy refuses (401, 403, 407) is replaced as for a TCP tunnel.

The TUN service and Android's VPN are clients like any other, on the core's TUN listener (`Daemon.OpenTunListener`): one association per app socket on desktop (`tun.SOCKS5Associate`), per app socket and destination on Android (hev-socks5-tunnel). The VPN carries only what `Daemon.VPNUDPPorts` lists, the ports above without QUIC (443) unless `tun.quic` is set, or a destination the routing sends directly; the listener keeps to that rule (`SOCKSServer.AllowUDP`, `Daemon.TunnelAllowsUDP`), and drops the rest without opening a stream. Apps' QUIC falls back to TCP: at once on desktop, whose TUN service answers with an ICMP unreachable, and after the app's own wait on Android, whose library cannot.

A TCP tunnel is a little faster than HTTP/3 through CONNECT-UDP. Refusing QUIC keeps browsers on the faster path, keeps a call's packets off a download's connection, and tells an app at once when the network cuts the connection (a TCP reset, where QUIC would wait for its own timeout).

## SOCKS and stream forwarding

`SOCKSServer` handles TCP clients with a per-client handler and optional concurrency limit. Its handshake supports the no-authentication method (or username and password when set) and CONNECT for IPv4, IPv6, or domain targets, and UDP ASSOCIATE ([above](#udp-connect-udp)). Ensure handshake failures, rejected connections, and forwarding errors release the relevant resources and slots.

`proxyBidirectional` forwards in both directions. Abnormal copy errors close both sides. Normal half-close drains for at most `halfCloseDrainTimeout`, currently two minutes. Optional idle handling is separate from the initial SOCKS handshake and CONNECT opening timeout.

| Resource / timeout | Current contract |
| --- | --- |
| Copy buffer | 64 KiB pool |
| Tunnel write buffer | Bounded at 64 KiB: a TCP tunnel's upload runs no faster with 1 MiB, at 16 times the memory |
| Client handshake timeout | Default 10 seconds; zero disables |
| Established idle timeout | Default zero; optional cutoff |
| Tunnel deadline methods | Explicitly return `errTunnelDeadline` |
| CONNECT opening timeout | Bounded opening operation, not stream lifetime |

A cancellation race can complete a connection after the caller stopped waiting. Preserve cleanup verified by `TestOpenTunnelContextClosesConnectionThatArrivesAfterCancellation`. Do not silently treat unsupported `net.Conn` deadline setters as successful.

## Lazy start and sleep

An engine (`internal/service`, `proxyEngine`) starts with no controller and builds one only when something needs Mozilla (`Daemon.useController`). `idleState.mu` guards the controller pointer, the use count, `sleeping`, `stopped`, the last wake failure, and the selected location; `idleState.wakeMu` serializes wakes and guards the engine's upstream configuration, so connections that arrive together wait for one wake and then all reserve the same controller. Wakes are network work and run outside `idleState.mu`. `runController` installs a new controller only while the engine is not stopped (`stopped`, set by `proxyEngine.stop` under the same lock); a wake that finishes after the stop closes its controller, so no renewal loop outlives its engine. After a failed wake, client connections get the failure until `wakeRetryAt` instead of waking again (`proxy.WakeRetryDelay`): 10 s after the first failure, doubling with each failure in a row up to 2 min, or the renewal path's delay for failures that retrying soon cannot fix (an account that must sign in again, a spent quota, a refused region, Retry-After). The connection test and the real-delay test retry at once, except after such a lasting failure (`proxy.LastingWakeFailure`). A network that comes back (`NetworkChanged(true)`) or a change of accounts ends the wait (`wakeAgainNow`); the app coming to the front ends it unless the failure is lasting (`RetryNow`, `retryNow`).

## Before changing lifecycle code

Trace who owns the socket, who holds the controller reference, who holds the pool-slot reference, and which close path releases each one. Cover the overlap that motivates the change: token update during slot replacement, rebuild during renewal, or shutdown during a pending operation. Add a regression test only for the changed failure mode.
