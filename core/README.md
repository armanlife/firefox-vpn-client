# Firefox Firefox VPN

An unofficial Go client for Mozilla's Firefox VPN (IP Protection) service. It signs in with Firefox Accounts, obtains a Guardian ProxyPass, and serves a local SOCKS5 CONNECT proxy through Mozilla's Fastly HTTP/2 (or experimental HTTP/3) proxies. Several accounts can be stored; when the active one has used its quota threshold (90% by default), the next one takes over without dropping open connections. A built-in web dashboard manages accounts, settings, logs, and connection tests.

The proxy carries TCP traffic from applications configured to use SOCKS5. Firefox does not need to be installed or running. There is no SOCKS5 UDP ASSOCIATE, BIND, TUN interface, or system-wide routing beyond Windows' proxy setting.

## Quick start

1. Run the program: double-click `firefox-vpn-core.exe` on Windows, or start `./firefox-vpn-core` in a Linux terminal. The window shows a status screen with a numbered list of actions and runs the proxy until you quit it; if the desktop app (or the Windows service, or a tray started with `-tray`) already runs the core for the same data folder, the window controls that one instead. A `user-data` folder is created next to the program; beside the desktop app (`firefox-vpn.exe`) the core uses the app's data folder.
2. Open the dashboard at <http://127.0.0.1:10820> (option **1** on the status screen).
3. On **Accounts**, choose **Add account** and sign in with a Firefox Account (email code, authenticator code, unblock code, and CAPTCHA prompts are shown when Mozilla asks for them).
4. Point applications at the SOCKS5 proxy `127.0.0.1:10810` (it also serves HTTP proxy clients). On Windows the tray sets Windows' system proxy to it by default while it runs (**Set system proxy**); choose **Clear system proxy** in the tray menu to leave it to applications set up by hand.
5. Optional: on the dashboard's **Servers** page, test the real delay and pick a server, or choose **Auto (fastest)**.
6. Optional, Windows: to start the proxy with Windows, choose **Install as a Windows service** on the status screen (asks for administrator rights); the tray icon then also appears at sign-in.

Everything else (location, ports, threshold, dashboard login, transport) is on the **Settings** tab or in `user-data/config.json`. See the [operator guide](doc/OPERATOR.md) for the tray icon, the Windows service, Linux/systemd, and troubleshooting.

**The `user-data` folder holds account credentials.** Keep it private; do not share or zip the program folder with it. Use only accounts you are authorized to use and respect Mozilla's terms.

## Project layout

```text
cmd/firefox-vpn-core/   Program entry: flags, run modes, one-shot commands; Windows icon resources
tools/winres/            Generator of the Windows icon and version resources
internal/service/        Service supervisor, dashboard and its API, API client
internal/service/web/    Dashboard page, styles, and script (embedded in the binary)
internal/proxy/          Accounts bridge, location selection, SOCKS5, H2/H3 sessions, renewal
internal/desktop/        Tray icon, terminal status screen, autostart, notifications
internal/winsvc/         Windows service
internal/logx/           Logging and the log file
internal/version/        Program version
internal/fxa/            Firefox Accounts sign-in, HAWK, OAuth, Fastly challenge
internal/guardian/       Guardian ProxyPass, quota usage, activation, status errors
internal/serverlist/     Remote Settings server list and Firefox record filters
internal/accounts/       Account storage, quota threshold, and failover policy
internal/config/         config.json schema, defaults, and the portable data folder
internal/controlplane/   Shared HTTP client for all control-plane API calls
internal/securefile/     Atomic owner-only writes for credentials and settings
internal/resolver/       Configurable DNS (DoH, DoT, plain) for Mozilla's servers and APIs
scripts/                 Linux systemd installer
doc/                     Maintained guides
```

Country flags in the dashboard come from [flag-icons](https://github.com/lipis/flag-icons) 7.2.3 (MIT, see `internal/service/web/flags/LICENSE`).

Tests sit next to the code they cover (`<name>_test.go`). See [ARCHITECTURE.md](doc/ARCHITECTURE.md) for package boundaries and call paths.

## Documentation

All maintained documentation is in English.

| Document | Purpose |
| --- | --- |
| [Documentation index](doc/README.md) | Task routing and the complete development reference |
| [Operator guide](doc/OPERATOR.md) | Running on Windows and Linux, systemd, troubleshooting |
| [Dashboard](doc/DASHBOARD.md) | Pages, API, login, and request security |
| [Multi-account mode](doc/MULTI-ACCOUNT.md) | Accounts, failover rules, data folder |
| [Configuration](doc/CONFIGURATION.md) | `config.json` and the files in the data folder |
| [Development workflow](doc/DEVELOPMENT.md) | Setup, scoped edit workflow, builds |

## Build and local verification

Run commands from the project root. The module declares Go `1.27.2`. Dependency versions are pinned in [go.mod](go.mod) and [go.sum](go.sum).

```powershell
go test -count=1 -timeout=180s ./...
go vet ./...
```

Build a Windows AMD64 executable (no CGO needed):

```powershell
$env:GOOS = 'windows'; $env:GOARCH = 'amd64'; $env:CGO_ENABLED = '0'
go generate ./cmd/firefox-vpn-core   # icon and version information, after a version change
go build -trimpath -o dist\firefox-vpn-core.exe ./cmd/firefox-vpn-core
```

The ordinary test suite uses local fixtures and synthetic credentials. Real account tests require separate, explicit opt-in; see [TESTING.md](doc/TESTING.md).

## Recorded verification and limits

Live H2 traffic, concurrent requests, an OAuth refresh accepted by Guardian, and natural ProxyPass renewal with an open connection have been verified against the real service. The multi-account service and the dashboard are covered by tests with local fixtures.

Account eligibility, server availability, and quotas depend on the service. Credentials are stored as plaintext JSON with owner-only permissions on Linux; there is no Windows DPAPI integration. The dashboard has no HTTPS: when it is opened from another device, its traffic (including passwords typed into it) crosses the network unencrypted.
