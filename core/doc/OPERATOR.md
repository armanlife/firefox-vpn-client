# Operator Guide

How to run, configure, and troubleshoot the service. The [dashboard guide](DASHBOARD.md) describes the web interface, [MULTI-ACCOUNT.md](MULTI-ACCOUNT.md) the account rules, and [CONFIGURATION.md](CONFIGURATION.md) every setting and file.

## Capabilities

- SOCKS5 CONNECT and an HTTP proxy on the same port, for IPv4, IPv6, and domain targets; no UDP ASSOCIATE, BIND, or TUN.
- Optional routing: the sites and networks of a region (Iran by default; also China, Russia, Afghanistan, Turkey, Indonesia, Brazil, or none), or any listed destination, directly through your own internet, the rest through Mozilla.
- Windows: the proxy always runs; the one choice is v2rayN's Set system proxy (the default, while the proxy runs) or Clear system proxy, applied by the tray or by the desktop app's core process.
- One or more Firefox Accounts; the next account takes over when the active one reaches the switch threshold (default 90% of its quota), keeps open connections, and returns to rotation after the quota reset.
- Upstream HTTP/2 over TLS (recommended) or experimental HTTP/3 over QUIC to Mozilla's Fastly proxies; one multiplexed session or a small pool.
- Location selection compatible with Firefox: recommended location by default, version-gated and locked records honored.
- Web dashboard for accounts, settings, live logs, and connection tests; all data in a portable `user-data` folder next to the executable.
- Tray icon (Windows and Linux desktops) with status, notifications, and quick actions; on Windows an optional background service that starts with Windows.

## Windows

1. Put `firefox-vpn-core.exe` in a folder you can write to (not `Program Files`), for example `C:\Tools\FirefoxVPN\`.
2. Double-click it. A window shows the status screen (below) and runs the proxy. The `user-data` folder appears next to the executable, and the log is written to `user-data\logs`, one file per day.
3. Choose **1 Open the dashboard** (or browse to <http://127.0.0.1:10820>), add an account on the Accounts page, and use `127.0.0.1:10810` as the SOCKS5 proxy in your applications (in a browser: SOCKS v5 with remote DNS).

Closing the window (with ✕ or **0 Quit**) stops the proxy. To keep it running without a window, start it with `-tray` (a tray icon) or install the Windows service. When a copy already serves the data folder (the desktop app's core, the service, or a tray), double-clicking the program opens the status screen for that copy instead: closing the window then leaves it running, and **Exit Firefox VPN completely** stops it. It never starts a second copy. Beside the desktop app (`firefox-vpn.exe` in the same folder) the program uses the app's data folder (`%LOCALAPPDATA%\Firefox VPN`, or `user-data` with a `portable` file), so double-clicking it shows the app's core.

### Status screen

Whenever the program runs in an interactive terminal (double-click, PowerShell, cmd, or a Linux terminal) without a command, it shows a status screen instead of the raw log: the state and location, the SOCKS5 and dashboard addresses, the active account with a usage bar, and the Windows service state, followed by a numbered list of actions. Type a number and press Enter:

```text
  What would you like to do?

     1  Open the dashboard in the browser
     2  Choose a server (test the real delay)
     3  Test the connection
     4  Restart the proxy
     5  Turn on system proxy
     6  Install as a Windows service (starts with Windows)
     7  Show the log
     0  Quit (stops the proxy)

  Enter a number and press Enter: _
```

The list adapts to the situation, so the numbers can shift: **Start Firefox VPN** replaces the proxy actions when nothing runs; with a service installed there is **Remove the Windows service**, and **Update the service to this file** when the service runs another file; **Turn on system proxy** (or **Turn off system proxy**) appears where the system proxy is supported (Windows); **Exit Firefox VPN completely** appears when the window controls a copy running elsewhere (a tray or the desktop app's core), not the Windows service. **0** closes the window: it stops the proxy that runs in the window, and leaves a copy running elsewhere running.

**Reset the dashboard login** (or **Create a dashboard login** when there is none) is the way back in after a forgotten dashboard password: it first shows what will happen, and after 1 it replaces the login with a new random username and password and shows them once; write them down. Every browser signed in is signed out.

**Choose a location** lists 1 Always the fastest, 2 Recommended, 3 Test the real delay again, and then every measured location from 4 on, lowest latency first; 0 goes back. In the log, 0 goes back.

Backspace corrects the number, Esc clears it (or goes back), and Ctrl+C closes the window. Persian and Arabic digits work as well. While a task runs (a measurement can take a minute), other choices wait with a message; exiting never waits.

On Windows the proxy never runs inside this window: the window starts the tray (`-tray`), which hosts the proxy, and keeps the tray icon present while a service or tray serves the folder. On Linux and macOS, where there is no tray from a terminal, the proxy runs in the window and **0** stops it. `-plain` prints the classic log instead, and a terminal that is not interactive (a pipe, systemd, or a redirect) always gets the plain log. The screen needs ANSI colors (Windows 10 1511 or later).

### Version

The version (`major.minor.patch`, for example `1.1.0`) is shown on the status screen, at the bottom of the dashboard's sidebar, and by `firefox-vpn-core -version`. When a newer copy serves the data folder (after an update), an older tray icon closes itself and the newer one takes its place.

### Tray icon

| Color | Meaning |
| --- | --- |
| Green | Proxy running |
| Blue | Proxy running, Windows' system proxy points at it (Set system proxy) |
| Amber | Starting, or waiting (no account yet, or every account waits for its quota reset) |
| Red | Error; the dashboard and the menu show the message |
| Grey | The service is not reachable (stopped, or still starting) |

The menu follows v2rayN's: **Open dashboard**, the system proxy modes (**Clear system proxy**, **Set system proxy**; the current one is checked), **Restart proxy**, and **Exit Firefox VPN (stops the proxy)**, which reads **Close icon (the service keeps running)** when the Windows service runs the proxy. It is the native Windows menu: a menu drawn like v2rayN's (a WPF program) would need a UI framework and make the program much larger. v2rayN's subscription items do not apply here. Hovering over the icon shows the connection state and, when connected, where the traffic leaves: the city and country of the public IP (for example "Firefox VPN: Connected · Amsterdam, Netherlands"), which also names Mozilla's recommended location; details and the Windows service are on the dashboard and the status screen. The dashboard's Help page explains the icon colors and the system proxy modes. A left click opens the dashboard. Notifications report account switches, errors, waiting states, and accounts that must sign in again. They come from "Firefox VPN" with the program's icon: the tray registers that name for the user (`HKCU\Software\Classes\AppUserModelId\FirefoxVPN.Proxy`) and writes the icon to `notification-icon.png` in the data folder. PowerShell still delivers them, hidden, but no longer appears as the sender.

When the background service runs, the tray only displays and controls it, and closing the icon leaves the proxy running. Otherwise the tray runs the proxy itself, and **Exit Firefox VPN** stops it. Only one tray runs per data folder; starting another opens the dashboard.

Start at sign-in comes with the Windows service: installing the service adds the value `FirefoxVPN` under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (`"<exe>" -tray -data-dir "<data>"`), and removing the service removes it. At sign-in a console window flashes briefly before the icon appears.

### Start with Windows (background service)

The service is for a core used on its own. Beside the desktop app (`firefox-vpn.exe` in the same folder) the status screen does not offer it and `-install-service` refuses: the app starts and stops that core, a service would keep running the old file after an app update, and a service cannot set the user's Windows proxy. A service installed earlier can still be removed there.

Install with **Install as a Windows service** on the status screen or from a terminal:

```powershell
.\firefox-vpn-core.exe -install-service      # asks for administrator rights (UAC) when needed
.\firefox-vpn-core.exe -uninstall-service
```

| Property | Value |
| --- | --- |
| Name / display name | `FirefoxVPN` / Firefox VPN proxy |
| Start type | Automatic: the proxy runs at boot, before anyone signs in |
| Account | `NT AUTHORITY\LocalService` (no administrator rights) |
| Command | `"<exe>" -service -data-dir "<data folder>"` |
| Recovery | Restart 10 seconds after a failure (also after a non-crash failure such as a busy port) |
| Log | `data\logs\firefox-vpn-YYYY-MM-DD.log` (the console is not available to a service) |

There is one `FirefoxVPN` service per computer; installing again (from any number of windows or copies) updates it and never creates a second one. A copy of the program in another folder shows the service as serving that other folder and offers **Move the Windows service to this folder** (in yellow) instead of **Install**, so the service is not moved by accident. Only one tray icon runs per data folder; extra copies exit quietly.

Installation grants LocalService modify access to the data folder and read/execute access to the executable (`icacls`), because folders inside a user profile deny other accounts. Installing from the status screen first stops the copy running in the background so the ports are free; removing the service lets the tray run the proxy again. The service belongs to one data folder: a copy of the program in another folder treats it as not installed.

#### Updating the program while the service runs

The service holds its executable open, so the file cannot be overwritten while it runs. To update:

1. Put the new executable in the same folder under another name, for example `firefox-vpn-core-1.1.exe` (same folder, so the same `user-data` folder, accounts, and settings).
2. Double-click it. The status screen shows the service as running another file and offers **Update the service to this file**. Choose it and confirm the administrator prompt: the service stops, switches to the new file, gets access to it, and starts again.
3. The old file is no longer used and can be deleted. The old tray icon closes itself when it sees the newer version; sign-in start is pointed at the new file.

To keep the original file name instead: run the old file, choose **Remove the Windows service**, exit, replace the file, run it, and choose **Install as a Windows service**. From a terminal, `-install-service` run from the new file does the same as the update, and `-uninstall-service` removes the service; `sc stop FirefoxVPN` and `sc delete FirefoxVPN` in an administrator terminal work too.

Installing the service also turns on start at sign-in for the user who installs it, so the tray icon shows and controls the service after every sign-in (`-install-service` from an administrator terminal leaves it alone). The tray then connects to the service through the local API token in `user-data\local-api.token` (see [DASHBOARD.md](DASHBOARD.md)).

Anyone who can replace the executable or read the data folder can act as the service. Keep the program folder writable only by you and administrators, and do not install the service from a shared or downloaded-files folder you do not control.

## Linux and systemd

On a desktop, run the binary from a writable folder like on Windows. On a server, install it as a service:

```bash
sudo ./scripts/install-systemd.sh install            # builds with Go, or BINARY=/path/to/firefox-vpn-core
sudo ./scripts/install-systemd.sh add-account        # terminal sign-in (email code), then restarts
sudo ./scripts/install-systemd.sh status
sudo ./scripts/install-systemd.sh logs
```

On a Linux desktop, `./firefox-vpn-core -tray` shows the tray icon (the desktop needs a StatusNotifierItem/AppIndicator host; GNOME needs the AppIndicator extension). **Show this icon at sign-in** writes `~/.config/autostart/firefox-vpn.desktop` (or under `$XDG_CONFIG_HOME`). Notifications use `notify-send` when it is installed.

The program and its data live in `/opt/firefox-vpn/` (`firefox-vpn-core` owned by root, `user-data/` owned by the `firefox-vpn` user). The unit runs with `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `NoNewPrivileges`, and write access only to the data folder, and restarts on failure.

The dashboard listens on `127.0.0.1:10820`. Reach it through an SSH tunnel (`ssh -L 10820:127.0.0.1:10820 server`), or set a login and open it to the network:

```bash
sudo ./scripts/install-systemd.sh set-dashboard-login
sudoedit /opt/firefox-vpn/user-data/config.json     # "dashboard": {"listen": "0.0.0.0:10820", ...}
sudo ./scripts/install-systemd.sh restart
```

Opening the dashboard to the network without HTTPS sends its traffic, including passwords typed into it, unencrypted. Prefer the SSH tunnel.

`uninstall` keeps `/opt/firefox-vpn`; `PURGE=1` deletes it including credentials.

## Command line

| Command | Effect |
| --- | --- |
| `firefox-vpn-core` | Run the service (dashboard + proxy) with the status screen in an interactive terminal, or the plain log otherwise |
| `-plain` | Print the log instead of the status screen |
| `-version` | Print the version and exit |
| `-tray` | Show the tray icon; it runs the proxy itself unless a service already serves the data folder |
| `-app` | Run the service for the desktop app, which starts the core this way; see [Desktop app mode](#desktop-app-mode) |
| `-install-service` | Windows: install or update and start the `FirefoxVPN` service (asks for administrator rights) |
| `-uninstall-service` | Windows: stop and remove the service |
| `-service` | Used by the installed service only |
| `-add-account` | Sign in on the terminal and store the account; restart a running service afterwards |
| `-list-accounts` | Print accounts, status, and usage |
| `-set-dashboard-login` | Set or remove the dashboard username/password; restart afterwards |
| `-data-dir PATH` | Use another data folder |
| `-verbose` | Log CONNECT destinations and debug lines regardless of the config |

Settings live in `config.json` and the dashboard, not in flags.

## Desktop app mode

The desktop app starts the core as a child process with `-app [-data-dir DIR] [-verbose]` when it opens and talks to it only through the dashboard API with the `X-Local-Token` header (the token in `user-data/local-api.token`). In this mode the process:

- runs the service (dashboard and proxy) in-process, with no tray icon and no status screen; on Windows it closes a console window that was opened for it;
- starts with the proxy off (`Daemon.Off`), so nothing connects and the system proxy is not set until the user presses the button in the app (`POST /api/power`); the tray, the terminal, and the service start on;
- logs only to the day's file in `user-data/logs`, because its standard output and error are pipes the app may never read; an error that stops it is also written to the standard error (see [App error line](#app-error-line)) before it exits;
- is the only desktop host of the data folder: it shares the single-instance lock with the tray icon, and refuses to start when a tray, another `-app` copy, or a service (the Windows service or a terminal copy whose dashboard API answers) already serves the folder;
- refuses to start when `dashboard.enabled` is false, since the app needs the API;
- applies `system_proxy.mode` like the tray (it reads the status every two seconds) and restores the previous Windows proxy setting when it stops;
- reports `can_exit: true` in `GET /api/status`.

The dashboard API answers as soon as the process has loaded `config.json` and the account list (tens of milliseconds; nothing waits for the network). The proxy then starts asleep: it listens on `proxy.listen` at once and `GET /api/status` reports `state.phase` `running` with `proxy.sleeping_since` set, but nothing is sent to Mozilla until a client connection through Mozilla, `POST /api/test`, or a real-delay test needs it (see [Sleeping when unused](#sleeping-when-unused)). With `system_proxy.mode` `set`, the Windows proxy is applied right away, since the listener is open.

It stops cleanly (system proxy restored, proxy and dashboard stopped) on `POST /api/app/exit` with the local token, on Ctrl+C or SIGTERM, and when its standard input ends. The app keeps the write end of the child's standard input pipe open for its whole life, so when the app quits or crashes the system closes it and the core follows. Anything written to the standard input is ignored. Only a pipe (or socket) is watched: with a terminal, the null device, or a file as standard input, the process runs until the exit request or a signal, and logs a warning.

| Exit status | Meaning |
| --- | --- |
| 0 | Stopped on request (exit API, end of standard input, signal) |
| 1 | Error: the service could not start (for example the dashboard is disabled, or `config.json` is invalid) |
| 2 | Bad arguments from the flag parser (an unknown flag or a stray argument); the usage text is written to the standard error, without an app error line |
| 3 | Another copy already serves the data folder; the app can use it through the API instead |
| 4 | Another program holds `dashboard.listen`; the app can offer another port and write it to `config.json` before starting again |

### App error line

When an `-app` run fails, the first line it writes to the standard error is machine-readable:

```text
app-error: <code> <detail>
```

The app reads lines that start with `app-error: `; `<code>` is one word, and `<detail>` is the rest of the line (it may contain spaces; line breaks in it are replaced with spaces).

| Code | Exit status | Detail | Lines |
| --- | --- | --- | --- |
| `dashboard_port_in_use` | 4 | The `dashboard.listen` address that is taken | This line only |
| `already_running` | 3 | The data folder | Followed by one line for people (`firefox-vpn-core: another copy …`) |
| `start_failed` | 1 | The error message | This line only; also for a mode conflict such as `-app -plain` |

A dashboard address held by another copy of this program that serves the same data folder is `already_running` (its API answers with this folder's token); one held by anything else, including a copy for another data folder, is `dashboard_port_in_use`. A taken proxy address does not stop the process: the dashboard runs and `GET /api/status` reports `state.code` `proxy_port_in_use` ([DASHBOARD.md](DASHBOARD.md#api)).

## Sleeping when unused

The proxy starts asleep: starting the program (the tray, the app mode, the service, or a terminal copy) opens the SOCKS5/HTTP port and the dashboard but sends nothing to Mozilla: no server list, no Firefox version lookup, no proxy pass, no session, no connection test or public IP check, no quota check, and no device registration. The first connection through Mozilla, a connection test, or a real-delay test connects it and waits for that: the server list and a pass (fetched together), the "fastest" measurement when that location is chosen, and the session, then the automatic connection test with the public IP check and the device registration, as a start used to do. The connection that woke it then goes through; it is delayed by that time (a few seconds, longer with "fastest"). Until then the status shows the persisted location for the configured choice, if any. If connecting fails, the proxy stays asleep, `GET /api/status` reports `proxy.wake_error` and `proxy.wake_failed_at`, and connections in the next 10 seconds fail with that error instead of asking Mozilla again; a connection test retries at once. When every account turns out to be unusable, the proxy restarts and waits like a start without a usable account.

Settings, Proxy, **Sleep when unused** (`proxy.idle_sleep`: never, 15 minutes (the default), 30 minutes, or 1 hour) saves the accounts when the proxy is not used. After that long without a connection through Mozilla, the proxy closes its session to Mozilla: no proxy pass is renewed and no quota is checked, so the account is not in use. The SOCKS5/HTTP port stays open. The next connection that needs Mozilla wakes it: a new pass and session for the same server (no new selection or delay test), which delays that first connection by a few seconds; a connection test or a real-delay test wakes it too. Direct connections (routing) do not wake it, and a connection that stays open keeps it awake. Meanwhile it does not look connected: Overview's badge, sidebar, and status dot turn indigo and say "Sleeping", the Uptime card becomes **Asleep for** (with the total uptime below), the tray icon is faded, and the tray tooltip and the status screen say "Sleeping".

## HTTP proxy and the Windows system proxy

The SOCKS5 address also serves HTTP proxy clients (HTTPS through CONNECT, plain `http://` requests forwarded), with the same SOCKS5 username and password (Basic login). The tray, the terminal, and the service run the proxy from their start; the desktop app starts it off, until the user presses its button. On Windows the other choice, as in v2rayN, is what happens to Windows' proxy setting: **Set system proxy** points it at the proxy, so browsers and programs that follow that setting go through the VPN without their own setup; **Clear system proxy** (the default, "Proxy only" in the app) turns Windows' system proxy off once, leaving the VPN to applications set up by hand. The choice is saved (`system_proxy.mode`), so the next start uses it. The tray and the app mode apply Set only while the proxy runs and restore the previous setting when the proxy stops, the program ends, or the tray icon is closed. The same choice is in the tray menu, Settings, Proxy, the desktop app, and on the status screen.

## Routing (your region's sites directly)

Settings, **Routing**, is off by default. Turned on, the sites and networks of the chosen **Region** (`routing.region`: Iran by default, China, Russia, Afghanistan, Turkey, Indonesia, Brazil, or None), private networks, and the destinations matched by the extra Direct rules go directly through your own internet: faster, not refused for a foreign address, and without using the accounts' quota. The region's rules come from two v2ray lists from Chocolate4U/Iran-v2ray-rules, a domain list (`geosite.dat`) and a network list (`geoip.dat`); they are downloaded on first use and again every 10 days into `user-data/routing`. The region's preset rules (listed in [CONFIGURATION.md](CONFIGURATION.md#routing)) are filled into the Direct rules, where they can be changed or removed; another region replaces them, and **Restore the region's rules** brings them back. Block rules refuse destinations, for example `geosite:ads`. A direct connection shows your real address to that site and is not protected by the VPN.

## SOCKS5 login

When the proxy listens on the network (for example `0.0.0.0:10810` on a VPS), anyone who finds the port could use it and spend the accounts' quota. Set **SOCKS5 username** and **SOCKS5 password** in Settings (`proxy.username`, `proxy.password`): clients must then log in (SOCKS5 username/password, RFC 1929), and refused clients are logged as warnings. The dashboard warns while the proxy is reachable from the network without them. In clients: `socks5h://user:password@host:10810`, or the SOCKS5 username and password fields of the application. Some browsers do not support SOCKS5 passwords themselves; use a local tool or extension in that case. A forgotten SOCKS5 password can be shown in Settings with the eye button next to it.

## DNS and filtering

The program resolves only its own destinations: Mozilla's Fastly proxy servers (`*.fastly-masque.net`) and the account, Guardian, and server-list services. Websites that applications open through the SOCKS5 proxy are sent by name to Mozilla's exit and resolved there, provided the application lets the proxy resolve names (in browsers: "Proxy DNS when using SOCKS v5", or `socks5h://`).

On a filtered network the system DNS may return wrong addresses for Mozilla's names. **Settings → DNS** chooses other servers: Automatic (Cloudflare, Google, and Quad9 over HTTPS, queried together), one of those providers, Cloudflare over TLS, or a custom list (`https://host/dns-query`, `tls://host`, or an IP address for plain DNS). Answers are cached for their TTL (30 seconds to 10 minutes). By default the system DNS is still used when none of the servers answers. The change applies to new connections at once; the proxy keeps running.

**Test DNS** resolves the four names through the selection and through the system DNS side by side and marks a system answer that is a block-page address (private, loopback, or Iran's filtering page) as **Filtered**: the network tampers with DNS. Answers that merely differ are normal for sites served from many places. Encrypted DNS does not help when the connections themselves are blocked or throttled (by address or by TLS server name); the API relay (`network.api_relay`, below) covers that case for the Mozilla services.

## Location, exit, and delay

### Choosing a location by real delay

**Test real delay** on the dashboard's Servers page tests the locations of the open tab (**Available** or **All servers**); **Choose a location** on the status screen tests every location. Results of a tab are merged into the earlier ones. For each location the test it opens a session with the active account's proxy pass and times a CONNECT to `www.google.com:443` (the better of two). Every location's server is on Mozilla/Fastly's anycast network, so the connection to the server reaches the same nearby Fastly edge for every location; only a request that travels on to the exit shows the real difference. The proxy must be running. A test takes a few seconds on a normal network and up to two minutes on a slow or filtered one; locked locations the account may not use show "not allowed for this account".

Results are sorted lowest first. **Use** sets that server (Manual); **Auto (fastest)** sets `proxy.country` to `fastest`, which measures at each proxy start (reusing a measurement younger than 30 minutes) and picks the fastest location the policy allows (locked ones only with `proxy.allow_locked`). If nothing answers, it falls back to the recommended location.


The configured location comes from Mozilla's server list. Without a country the recommended (anycast) location is used. The **Exit** on the Overview page and the connection test report the address websites actually see, which may be IPv4 or IPv6 and can differ between destinations. Hostname persistence does not pin a physical server or exit IP.

The connection test's **total** includes opening a CONNECT stream, the TLS handshake to the test site, and its first response; it is not ICMP latency.

## Stability and renewal

- The ProxyPass (about ten minutes) renews two minutes before expiry on the existing upstream session; open connections continue.
- Transient Guardian failures retry within the request and again after 30 seconds. Failures that retrying cannot fix soon (sign-in required, region refused, not entitled) back off for 15 minutes; spent quota waits for its reset. The Overview page shows the last renewal error and the next attempt.
- A renewal that exceeds two minutes is cancelled and retried; the process exits only if it cannot unwind within 30 more seconds (systemd restarts it).
- While no network is connected (for example right after the computer starts, before Wi-Fi connects), the proxy does not try Mozilla: the dashboard and the tray say "Waiting for a network connection" (without a notification), and it starts within two seconds of Wi-Fi or a cable connecting. Only the network adapters are looked at (one that is up with a gateway counts; VMware, Hyper-V, and WSL adapters without one do not); a network without internet still counts and the start then retries. This always applies.
- If the proxy cannot start (for example the SOCKS port is in use), the dashboard shows the error and the service retries every 30 seconds (5 seconds right after a network connected).

## Troubleshooting

### Waiting: add an account / no usable account

The proxy starts when at least one enabled account can supply a pass. With accounts present, the Accounts tab shows why each one is not usable: threshold reached (until the reset date), needs sign-in, unavailable (rejected, retried after 15 minutes), or disabled.

### Needs sign-in (`reauth_required`)

Mozilla rejected the stored credentials (for example after the account's sessions were revoked). Use **Sign in again** on the account.

### Guardian returns HTTP 451 (`region_unavailable`)

Guardian does not serve the region the API requests come from, or the network blocks Mozilla's sign-in, Guardian, or server list. Set up your own relay and put its URL in **Settings → Advanced → Relay for Mozilla's services** (`network.api_relay`). Only these requests use it (the account sign-in and tokens, Guardian, the server list, the geo files, and flags); the VPN traffic never does.

The relay takes `?url=<target>` and sends the same method, headers, and body to the target; it relays only Mozilla's, GitHub's, and jsDelivr's hosts, so it is not an open proxy, and answers a refusal with an `X-Relay-Error` header, which the program reports. Two ready-made relays are in [scripts/relay](../scripts/relay):

- **Cloudflare Worker** (`worker.js`, free): Cloudflare dashboard → Workers & Pages → Create → Worker, paste the file, set `KEY`, Deploy. The URL is `https://NAME.ACCOUNT.workers.dev/?key=KEY`. Its requests leave from the Cloudflare location nearest you, so it helps against blocking but not always against Guardian's region check.
- **PHP** (`relay.php`, PHP 7.3+ with curl): upload it to a host that serves HTTPS, set `$KEY`; the URL is `https://example.com/relay.php?key=KEY`. Its requests leave from the host's country.

The URL must be `https://`: the sign-in and the account tokens cross the relay, and whoever runs it can read them, so use only a relay you run yourself. Set a `KEY`; without it anyone who finds the URL can use the relay for those hosts.

### Fastly challenge, CAPTCHA, or HTTP 406

Mozilla's account API is behind a Fastly anti-bot check. Proof-of-work challenges are solved automatically; image CAPTCHAs appear in the dashboard sign-in dialog. Background token refreshes cannot show a CAPTCHA; if one blocks them, the account eventually needs a new sign-in.

### Location is locked

Locations marked locked in Mozilla's list are offered by Firefox only to entitled accounts. Choose another location, use the recommended one, or enable **Allow locations marked as locked** if the account is entitled. A persistent CONNECT 403 on a location usually has the same cause.

### A site on an unusual port does not open

Mozilla's proxy connects only to the web ports **80, 443, 8080, and 8443**; for every other port (for example `http://203.0.113.5:9898/`, SSH on 22, or DNS on 53) it answers `502 Bad Gateway`. This is Mozilla's rule for its browser VPN and cannot be changed by this program. The log says `Mozilla's proxy does not connect to port …`, and SOCKS clients get the reply "connection not allowed by ruleset"; the dashboard shows a note on Overview and explains it under **Help**. Serve the site on one of the four ports, or let the browser reach it without the proxy (Firefox: Settings, Network Settings, **No proxy for**). Measured on 2026-10-10 through the tunnel.

### Port already in use

The proxy or dashboard address is taken by another program (or another copy of this one). Change `proxy.listen` or `dashboard.listen`, or stop the other program. Do not stop unrelated software to free a port. While the proxy address is taken, the status shows the error with the address (`state.code` `proxy_port_in_use` in `GET /api/status`) and the start is retried every 30 seconds; a new `proxy.listen` saved in Settings applies at once. The desktop app's core process exits with status 4 and an `app-error: dashboard_port_in_use` line when the dashboard address is taken ([App error line](#app-error-line)).

### The Windows service stops right after starting

Usually another copy (a console window or a tray started before the service) holds the proxy or dashboard port; the service retries every 10 seconds. Close the other copy, or quit its tray. The reason is in the day's log in `user-data\logs`. If the log shows access errors, the folder or executable moved: run `-install-service` again.

### Log files

The log is written to `user-data/logs`, one file per day (`firefox-vpn-2026-10-10.log`, by local date). The last seven days are kept: when the eighth day starts, the oldest file is deleted. Ordinary logging writes a few kilobytes a day; as a safety limit a day's file stops at 10 MB (only verbose logging under heavy traffic gets there) with a note, and logging continues in the next day's file. Several processes (the service and a tray or status screen) can write the same file. When the day's file is deleted while the program runs, it is created again within ten seconds.

### The tray icon is grey

The tray cannot reach the service: the service is stopped or still starting, the dashboard is disabled in `config.json` (`dashboard.enabled`), or `user-data\local-api.token` is unreadable. The menu names the service state.

### HTTP/3 times out

Live HTTP/3 has not been verified to work with Mozilla's proxies; UDP may also be blocked on the network. Use HTTP/2.

## Credentials and limits

- Per account, `user-data/accounts/<id>/credentials.json` holds the OAuth access token (about one day), the refresh token for the scope `profile https://identity.mozilla.com/apps/vpn`, and the Firefox Account password, encrypted with a key kept in `user-data/accounts/secret.key`. The password lets the program sign in again by itself when Mozilla revokes the tokens. The encryption only keeps the password out of plain sight: anyone with the whole data folder can recover it, so keep the folder private and never share it. Sign-in itself still sends only `authPW`, derived from the password locally as Firefox does.
- Each account appears in its Mozilla account's connected services as **Firefox's built-in VPN**. Tokens can be revoked there; the program then signs in again with the stored password, or asks for **Sign in again** when Mozilla wants a confirmation code.
- On Windows the files take the data folder's normal permissions; on Linux they are `0600`.
- The dashboard has no HTTPS.
- Account eligibility, server availability, and quotas are decided by Mozilla. Respect the service's terms and quotas.
