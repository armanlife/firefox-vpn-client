# Web Dashboard

The service embeds a web dashboard and a JSON API in the executable. It is enabled by default on `http://127.0.0.1:10820` and keeps running while the proxy itself is stopped, waiting for an account, or restarting after a settings change.

## Pages

| Page | Content |
| --- | --- |
| Overview | Status banner (state, location, server, proxy address with copy, transport, exit IP), Test connection, Restart, and Turn off / Turn on (`POST /api/power`, the same switch as the app's power button; Off closes the proxy port and shows the state Off); tiles for active-account usage, ready accounts, last latency, uptime and pass renewal; active account with quota bar and threshold mark; connection test with a stage timeline; proxy details; recent log lines |
| Servers | Server selection (Auto (recommended), Auto (fastest), or Manual) with switches; the active server is marked **Active**; a note names the Firefox version the server list is evaluated for; **Available** (default: the open locations, plus locked ones the real-delay test reached, which proves the account may use them; "Allow locked" in Settings only permits choosing locked locations) and **All servers** (everything, with an explanation of locked); every location with its country flag, server, and real delay; sort by real delay or name, search; **Test real delay** (tests the locations of the open tab only); Use per location |
| Accounts | Accounts in priority order with status, reason, quota bar, reset date; drag a card by its position number to change the order (`enableAccountDrag`; the arrows do the same, also on phones, where browsers do not drag), Use now (not for an account that must sign in again); the active account shows **Active** in place of **Ready**, so every row keeps one line of chips; Refresh quota, Sign in again, Enable/Disable, Remove; the quota and button columns have fixed widths so the rows line up; Add account. The sidebar badge counts accounts that need attention |
| Logs | Live log (server-sent events) with level filter, text filter, follow, clear |
| Settings | Every `config.json` setting except `dashboard.enabled` and the account order, in sections with a section index: Dashboard, Connection, Local proxy, DNS, Routing, Accounts, Advanced. Each setting is a row (icon, name, a one-line hint, and its control at the end; lists and paired fields under the text, and every control under the text on a narrow screen). Listen addresses are a choice (this device only, 127.0.0.1, or all networks, 0.0.0.0; another host from `config.json` is kept as a third choice) plus a port; durations are choices (a value from `config.json` that is not one is added to them); the protocol and the Windows system proxy mode are two-way switches. The save bar (Save, Discard) shows only while the form differs from the saved settings (`collectSettings` against the snapshot taken by `loadSettings`) |
| Help | What the proxy can and cannot do, one card each: connecting applications (any SOCKS5 client: the SOCKS5 address and a `socks://base64(user:password)@host:port#name` link for v2rayN, v2rayNG, and NekoBox, both with Copy, built from the settings by `renderHelp`; a proxy listening on all addresses is shown with the dashboard's address; the password is not displayed, only copied), only ports 80, 443, 8080, and 8443 (`#help-ports`), TCP only (`#help-udp`), the two Windows system proxy modes (Set, the default, and Clear), the tray icon colors, quota and accounts, locked servers, shared public IP, your region's sites directly (routing), filtered networks, logs. Static text in `index.html` |

The sidebar order is Overview, Servers, Accounts, Logs, Settings, Help; the bottom of the sidebar shows the location and the program version. The page header carries the connection state, the dark/light switch, and Sign out (with a login). Pages are addressable (`#overview`, `#locations`, `#accounts`, `#logs`, `#settings`). Country flags are SVG files bundled in `web/flags/` (flag-icons 7.2.3, MIT; the recommended location shows a star) and are cached by the browser for a week; every other response is `no-store`. The layout is a sidebar (a top bar on narrow screens) with a dark theme by default; it follows the system's light or dark preference until the theme switch is used, which is remembered in the browser. The page uses no external resources (system fonts, inline SVG icons).

### Adding an account

**Add account** asks for the Firefox Account email and password and starts a background sign-in. The dialog then shows whatever Mozilla asks for: an emailed verification code, an authenticator (TOTP) code, an emailed unblock code for a sign-in Mozilla considers unusual, a confirmation link, or a Fastly image CAPTCHA. Wrong codes can be retried. On success the account joins the end of the priority order and its quota is read. The password is never stored.

**Sign in again** on an account that needs it starts the same flow; the existing account (same email) gets the new credentials and becomes ready.

### Locations and real delay

See [OPERATOR.md](OPERATOR.md#choosing-a-location-by-real-delay) for how the real delay is tested and how "Auto (fastest)" works. The wording follows v2ray clients (servers, real delay, active, auto/manual), which most users know.

### Overview cards and the recommended location

Overview has four cards: **Active account** (its quota gauge; the tooltip counts ready accounts and the switch threshold), **Latency** (the last connection test), **Speed**, and **Uptime**. Mozilla's recommended location names no place in the server list, so the header, the sidebar, and the tray tooltip show the country and city of the public IP for it ("Netherlands · Amsterdam (recommended)") with that country's flag, once the public IP check has run.

### Data folder

Overview's Proxy card shows the data folder; the bottom of Settings shows the program folder (the running core's executable, `program_dir` in `GET /api/settings`) and the data folder, each with a copy button; the version is in the sidebar. `POST /api/open-folder` (used by the desktop app) shows the data folder in the file manager of the computer the program runs on, only from that computer. When the tray or the status screen runs the service, it opens directly; the Windows service cannot reach the desktop, so it raises `open_folder_request` in the status and the tray opens the folder within a few seconds.

### Speed

Overview's **Speed** card shows the current download and upload speed (the server averages the last three seconds, `proxy.Traffic`) and what was transferred since the proxy started; the tooltip splits it into through Mozilla and directly (routing). The counts cover the SOCKS5 and HTTP proxy clients, not the program's own requests.

### Connection test

The test also runs by itself after the proxy starts and after its upstream session was rebuilt, so the result and the public IP are ready on Overview.

ICMP ping cannot cross a CONNECT proxy, so **Test connection** sends `GET https://www.google.com/generate_204` through the tunnel and reports the total time and HTTP status and three consecutive stages: opening the tunnel, the TLS handshake, and the response (from sending the request to its first byte; `response_ms`). Below them is the **public IP**, the address websites see (Mozilla's exit): the IPv4 and the IPv6 address (sites reachable over IPv6 see the IPv6 one), with the country flag, city, country, and network from the public IP check (which always runs); a click on an address copies it. The Overview header shows the IPv4 address as a chip after the startup check (the tooltip has both). The word is "public IP" rather than "exit", which read like a command.

### Notes on refused requests

When the proxy refused a request in the last five minutes because of a limit, Overview shows an orange note under the status banner (it goes away five minutes after the last refusal), with how often and when, and a link to the matching Help card: a port Mozilla's proxy does not connect to (`proxy.NoticePort`), or a SOCKS command other than CONNECT such as UDP (`proxy.NoticeCommand`). Each note is a separate box with the latest destinations (up to three names or addresses with the port) and its own close button. The daemon keeps them in `proxy.Notices` (one entry per kind and detail, at most 20, across proxy restarts; destinations only in memory, the log keeps them redacted unless verbose) and `GET /api/status` returns them as `notices`. Closing a note hides it in this browser (`localStorage`) until the next refusal of the same kind.

## Access and security

Password fields have a show/hide button. The SOCKS5 password, the new dashboard password, and the Firefox Account password are text fields masked with CSS (`-webkit-text-security`), not `type=password`, so the browser's password manager neither offers saved passwords nor suggests a generated one there; browsers without that CSS property fall back to `type=password` (`setupSecrets` in `app.js`). The SOCKS5 password is stored in `config.json` and shown with the button when it is forgotten. The dashboard password is stored only as a hash and cannot be shown; set a new one in Settings or with `-set-dashboard-login`. The Firefox Account password is never sent to the page.

| Setting | Behavior |
| --- | --- |
| No `dashboard.username` (default) | No login. Only requests whose `Host` is an IP address or `localhost` are served, which defeats DNS rebinding from web pages. |
| `dashboard.username` with a password | Login page; API calls need an `HttpOnly`, `SameSite=Strict` session cookie valid for 400 days (the longest browsers keep a cookie). The cookie is signed, not stored: `<expiry>.<HMAC-SHA256 of the expiry, username, and password hash>` under the data folder's `dashboard.key`, so it survives restarts, and a new username or password signs every browser out; signing out ends it until the program restarts (the browser deletes it too). Failed logins are delayed by one second. The password is stored as a bcrypt hash. |
| `X-Local-Token` header | A request carrying the content of `local-api.token` in the data folder skips the `Host` check and the login. The tray uses it. Browsers cannot attach the header cross-origin without a CORS preflight, which the dashboard never grants; anyone who can read the data folder can already read the credentials. |
| `dashboard.listen` on a non-loopback address | Reachable from other devices. Without a username a warning is shown and logged. There is no HTTPS: passwords and data cross the network unencrypted. |
| No dashboard login | Every page shows a warning box at the top, stronger when the dashboard is reachable from other devices, with **Set a password**, which opens Settings at the Dashboard section with the cursor in Username (`renderWarnings`). A proxy open to the network without a login gets a box of its own, with **Set a login**. |

Every state-changing request must be `application/json` and, when the browser sends `Origin`, same-origin; responses carry a strict Content-Security-Policy, `X-Frame-Options: DENY`, and `no-store` caching. API responses never include tokens, passwords, or the password hash. Server data is rendered with `textContent` only.

To require a login, open Settings, enter a username and a password (at least six characters) in the Dashboard section, and save; the page then asks for the login. Clearing the username removes it. On a headless machine, use `firefox-vpn-core -set-dashboard-login` instead (then restart). A forgotten password is reset on the status screen: **Reset the dashboard login** asks first and then shows a new random username (`admin-` and four characters) and password (16 characters, without look-alike characters) once (`POST /api/dashboard/reset-login`, only with the local token). The tray and the status screen keep working with a login, through the local token. To reach a server's dashboard without exposing it, use an SSH tunnel: `ssh -L 10820:127.0.0.1:10820 server`.

Changing `dashboard.listen` from Settings moves the dashboard after the response; the page follows to the new address. `dashboard.enabled` can only be changed in `config.json`, so the dashboard cannot disable itself.

## API

All paths are under `/api`. Errors are `{"error": "message"}` with a 4xx/5xx status.

State codes in `GET /status` (`state.code`), for clients such as the desktop app that offer a fix instead of showing the message:

| `code` | Meaning | `address` |
| --- | --- | --- |
| `proxy_port_in_use` | The proxy cannot start because another program holds `proxy.listen`; the phase is `error`, and the start is retried every 30 seconds. Saving a new `proxy.listen` (`PUT /settings`) restarts the proxy on it at once. The code goes away with the next state | The taken `proxy.listen` address |

The proxy checks its address before anything else, so the code appears even without an account and before any request to Mozilla; the port itself opens for clients only once the upstream is ready.

| Method and path | Purpose |
| --- | --- |
| `GET /session`, `POST /session`, `DELETE /session` | Login state, log in (`{username, password}`), log out |
| `GET /status` | Engine state, proxy, ProxyPass status, active account, exit, last test, account counts, dashboard exposure. `state` holds `phase` (`starting`, `running`, `waiting`, `error`, and `off` while the phone app has turned the proxy off through `mobile.SetOn`), `message` for people, `since`, `retry_at` while a failed start waits to retry, and, for a problem a client can act on, `code` and `address` (both omitted otherwise; see below) `proxy` (present while the engine runs, asleep or not) adds `sleeping_since` while the proxy holds no upstream session (from its start until first used, and after `proxy.idle_sleep`; `pass` is then absent, and `upstream`, `country_*`, `selection_source` show the persisted choice or are empty until the first connection), and `wake_error` with `wake_failed_at` after a failed attempt to connect (cleared by a successful one) |
| `POST /test` | Run the connection test (proxy must be running; a sleeping proxy is woken first, which also retries at once after a failed wake; 409 with the error when it cannot connect) |
| `POST /proxy/restart` | Restart the proxy engine |
| `POST /power` | `{"on": bool}`: turn the proxy off (port closed, nothing connects to Mozilla) or on again |
| `GET /accounts` | Accounts in priority order with status and usage |
| `POST /accounts/order` | `{ids: [...]}` listing every account once |
| `POST /accounts/{id}/activate` | Use this account now |
| `POST /accounts/{id}/enabled` | `{enabled: bool}` |
| `POST /accounts/{id}/refresh` | Read the account's quota (`HEAD`, no pass minted) |
| `DELETE /accounts/{id}` | Remove the account and its credentials |
| `POST /signin` | Start a sign-in: `{email, password}`, or `{account_id}` to sign an account in again with its stored password (409 without one) |
| `GET /signin/{id}` | Sign-in state: `step` (`working`, `need_email_code`, `need_totp`, `need_unblock_code`, `need_captcha`, `need_email_link`, `done`, `failed`, `cancelled`), `message` (the instruction), `error` (why the last answer or the sign-in was refused, for example "Wrong or expired code…"; the dialog shows it in a red box), `captcha` (data URL), `account_id` |
| `POST /signin/{id}` | Answer the current step: `{value}` |
| `DELETE /signin/{id}` | Cancel |
| `GET /settings`, `PUT /settings` | Read the config (password hash removed) / save `{config, dashboard_password}` |
| `GET /locations` | Locations from the server list: code, name, city, server, locked, recommended, and the last measured `ping_ms` or `ping_error`; `pinged_at` |
| `POST /locations/ping` | `{codes}` (optional): test the real delay of those locations, or of every location, through the tunnel (proxy must be running; 409 otherwise); the results are merged into the earlier ones and returned sorted. Can take up to two minutes |
| `POST /app/exit` | Stop the proxy and end the process that hosts it (the tray, or the desktop app's core process started with `-app`); only with the local token (403 otherwise), 409 for the Windows service. `GET /status` reports `version` and `can_exit` (true in the tray and the app mode) |
| `POST /dns/test` | `{servers}` (the unsaved form; omitted = saved): resolve the program's four destination names through those servers and through the system DNS; per name the addresses, time, answering server, errors, `differs` (no address in common: normal for sites served from many places), and `filtered` (the system answered with a block-page address: private, loopback, link-local, or Iran's filtering page); the page marks only `filtered` as a warning |
| `POST /location` | `{country}`: a country code, `fastest`, or empty for the recommended location; clears an exact server and restarts the proxy |
| `GET /logs?after=N`, `GET /logs/stream` | Buffered log entries (last 2000) / server-sent events |

Settings changes to `proxy`, `network`, or `accounts.quota_check_interval` restart the proxy engine (open tunnels end). The threshold, logging, dashboard login, routing, and the system proxy switch apply immediately. Settings has a **Routing** section (**Country** (`routing.region`: Iran, China, Russia, Afghanistan, Turkey, Indonesia, Brazil, or None; the region's sites and networks go directly), the switch, **Block ads** (a shortcut that adds or removes `geosite:category-ads-all` in the Block list, which shows it too), the Direct rules (the region's presets filled in, editable, with **Restore the region's rules**) and the Block rules one per line, the name lookup switch, the update interval in days, the list URLs, **Update the lists now**, and the state (on, off, or not working, with why) and the files (when they were updated, names, sizes); `GET /api/routing` (`enabled`, `active`, `region`, `direct`: the Direct rules, `region_rules`: the region's presets, `summary`, `error`, `files`, `updating`, `last_check`, `last_error`, `counts`), `POST /api/routing/update`) and **Test a destination** (a name, an address, host:port, or a URL: where it goes, the rule that decides, and a warning when it goes through Mozilla on a port Mozilla refuses; `POST /api/routing/test`), and, on Windows, the system proxy mode under Proxy (`POST /api/system-proxy {mode}`, `mode` `set` or `clear`; anything else is a 400).

## Source map

| Concern | Source |
| --- | --- |
| Server, routes, request policy, login | [dashboard.go](../internal/service/dashboard.go) |
| API handlers and views | [dashboard_api.go](../internal/service/dashboard_api.go) |
| Background sign-in steps | [signin_flow.go](../internal/service/signin_flow.go) |
| Connection test | [conntest.go](../internal/proxy/conntest.go) |
| Log buffer and stream | [loghub.go](../internal/logx/loghub.go) |
| Supervisor and account/settings operations | [daemon.go](../internal/service/daemon.go), [engine.go](../internal/service/engine.go) |
| Page, styles, script | [web/](../internal/service/web/index.html) |

Tests: `internal/service/dashboard_test.go` (request policy, login, settings, accounts, sign-in with code retry, logs, connection test).
