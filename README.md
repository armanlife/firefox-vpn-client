# Firefox VPN

**Mozilla's free VPN proxy on your whole computer and your phone, with as many accounts as you like.**

[فارسی](README_fa.md)

Firefox has a built-in VPN: every Firefox Account gets 50 GB a month through Mozilla's own proxy servers. Firefox VPN takes that service out of the browser. It runs it for every app on Windows and Android, and as a headless proxy on Linux. Several accounts work together, so a month's data no longer ends at 50 GB.

> **Unofficial.** This project is not made, endorsed, or supported by Mozilla. Firefox and Mozilla are trademarks of the Mozilla Foundation.

## Why Firefox VPN

- **Free, from a trusted network.** The traffic goes through Mozilla's own servers (Fastly), the same ones Firefox uses. There is no third-party VPN company in the middle.
- **More data with more accounts.** Add several Firefox Accounts. When the active one has used 90% of its data, the next one takes over by itself, without dropping your connections.
- **Every app, not only the browser.** A real VPN on Android. A system-wide proxy on Windows. A SOCKS5 and HTTP proxy for anything else.
- **Fast where it matters.** Your own country's sites can open directly, without the VPN. They load faster and use no data.
- **Made for filtered networks.** Encrypted DNS, HTTP/3 with an automatic fallback to HTTP/2, a check that detects tampered DNS, and an optional relay of your own for when signing in to Mozilla is blocked.
- **Small and light.** About 14 MB for Android and 18 MB for Windows. No ads, no tracking, and no server involved but Mozilla's.

## Features

### Connection

- One tap to connect. The app always starts disconnected and connects only when you ask.
- Locations from Mozilla's server list, each with its flag and real delay. Choose one yourself, or let the app pick the recommended or the fastest.
- HTTP/2 or HTTP/3 (QUIC). Where QUIC is blocked, the app falls back to HTTP/2 by itself.
- Pauses the connection to Mozilla when nothing uses it, so the accounts rest. The next request wakes it in a few seconds.
- Waits quietly while there is no network, and reconnects at once on a new one.
- A connection test with every stage timed, and the public IP address, country, and network that websites see.

### Accounts

- Sign in with a Firefox Account inside the app, with every step Mozilla may ask for: an email code, an authenticator code, or an image check.
- The data left on each account, and the date it resets.
- Automatic switching between accounts at a share you choose.
- A reminder when the active account runs low and no other is ready.
- Expired sign-ins are renewed by themselves, with the password stored on your device.

### Routing

- Sites and addresses of your country open directly: Iran, China, Russia, Afghanistan, Turkey, Indonesia, or Brazil.
- Rules in the v2ray format (geosite, geoip, domain, keyword, IP ranges), with lists from Chocolate4U or Loyalsoldier, updated automatically.
- Your own Direct and Block lists.
- Ad blocking with one switch.
- On Android, choose which apps use the VPN.
- Test any address to see where it goes and which rule decides it.

### DNS

- Encrypted DNS: DNS over HTTPS or TLS, from Cloudflare, Google, or Quad9, or your own servers.
- A DNS test that compares the answers with your network's own and tells you when your network tampers with DNS.

### Android

- A full VPN for every app, or a local proxy only.
- A Quick Settings tile and a home-screen button to connect in one tap.
- The speed and the location in the notification.

### Windows

- A proxy for the whole system, or only for the apps you set up.
- Lives in the tray and, if you like, starts with Windows.
- Share the proxy with other devices on your network, protected with a login.

### macOS

- The same app in the menu bar, with the system proxy for every network (Wi-Fi, Ethernet), and starting at sign-in.
- One file for Apple silicon and Intel Macs.

### Linux

- The same app, with the system proxy (GNOME's setting), the tray, and starting at sign-in, installed with [one command](#install-from-the-terminal).
- For servers, a headless core as a systemd service, also with one command.
- A web dashboard to manage everything from a browser: status, accounts, locations, settings, and logs.

### For everyone

- 15 languages: English, فارسی, 简体中文, 繁體中文, Русский, Türkçe, العربية, Azərbaycan, Bahasa Indonesia, Español, Français, Magyar, Português, Tiếng Việt, and বাংলা. Persian and Arabic read right to left, and Persian dates follow the Solar Hijri calendar.
- Light and dark themes.

## Download

The newest version, straight from [Releases](https://github.com/armanlife/firefox-vpn-client/releases/latest):

<table>
<tr><th>System</th><th>Download</th></tr>
<tr><td>Android</td><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Android-universal.apk"><img src="https://img.shields.io/badge/APK-Universal-1a7f37?logo=android&logoColor=white" alt="APK Universal"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Android-arm64-v8a.apk"><img src="https://img.shields.io/badge/APK-ARMv8-2da44e?logo=android&logoColor=white" alt="APK ARMv8"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Android-armeabi-v7a.apk"><img src="https://img.shields.io/badge/APK-ARMv7-4ac26b?logo=android&logoColor=white" alt="APK ARMv7"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Android-x86_64.apk"><img src="https://img.shields.io/badge/APK-x64-6fdd8b?logo=android&logoColor=white" alt="APK x64"></a></td></tr>
<tr><td>Windows</td><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Windows-Setup-x64.exe"><img src="https://img.shields.io/badge/Setup-x64-0550ae?logo=windows&logoColor=white" alt="Setup x64"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Windows-x64.zip"><img src="https://img.shields.io/badge/Portable-x64-0969da" alt="Portable x64"></a></td></tr>
<tr><td>macOS</td><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-macOS.dmg"><img src="https://img.shields.io/badge/DMG-Universal-24292f?logo=apple&logoColor=white" alt="DMG Universal"></a></td></tr>
<tr><td rowspan="2">Linux</td><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Linux-amd64.tar.gz"><img src="https://img.shields.io/badge/App-amd64-e36209?logo=linux&logoColor=white" alt="App amd64"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/Firefox-VPN-Linux-arm64.tar.gz"><img src="https://img.shields.io/badge/App-ARM64-e36209?logo=linux&logoColor=white" alt="App ARM64"></a></td></tr>
<tr><td><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/firefox-vpn-core-linux-amd64.tar.gz"><img src="https://img.shields.io/badge/Core-amd64-f0883e?logo=linux&logoColor=white" alt="Core amd64"></a><br><a href="https://github.com/armanlife/firefox-vpn-client/releases/latest/download/firefox-vpn-core-linux-arm64.tar.gz"><img src="https://img.shields.io/badge/Core-ARM64-f6a35e?logo=linux&logoColor=white" alt="Core ARM64"></a></td></tr>
</table>

- **Android** 7.0 or later: ARMv8 fits almost every phone; Universal fits all of them and is larger.
- **Windows** 10 or 11: Setup installs the app for you alone, with no administrator rights, and a new version installs over the old one. Portable is a `Firefox VPN` folder: unzip it anywhere and run `firefox-vpn.exe`. Either way, your accounts and settings stay in `user-data` beside the app.
- **macOS** 12 or later: open the DMG and drag Firefox VPN to Applications. The app is not signed by Apple, so the first time macOS refuses to open it: in System Settings > Privacy & Security, choose Open Anyway. The command below installs it without that step.
- **Linux:** the app for the desktop (amd64 is a usual Intel or AMD PC; ARM64 is a Raspberry Pi or an ARM laptop), or the core alone with its web dashboard for servers; install either with one command, below.

### Install from the terminal

The app on macOS, or on a Linux desktop, for you (no sudo):

```bash
curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | bash -s -- desktop
```

On macOS it goes into Applications and keeps your accounts in `~/Library/Application Support/Firefox VPN Client`. On Linux it goes into `~/.local/opt/firefox-vpn-client` and the applications menu, and keeps your accounts in `~/.local/share/firefox-vpn-client`; the tray icon needs `libayatana-appindicator3-1` (Debian, Ubuntu) or `libappindicator-gtk3` (Fedora, Arch); on GNOME, also the AppIndicator extension. To remove it: `... | bash -s -- remove-desktop`.

The core as a service, for a Linux server (amd64 or ARM64, with systemd):

```bash
curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | sudo bash
```

Either one downloads the newest release, checks it against the release's checksums, and installs it. For the service, then:

```bash
sudo firefox-vpn add-account    # sign in to a Firefox Account
sudo firefox-vpn status         # the service and its state
sudo firefox-vpn help           # every command
```

The dashboard is at http://127.0.0.1:10820, and the proxy (SOCKS5 and HTTP) at `127.0.0.1:10810`. Run the same command again to update; accounts and settings stay. `sudo firefox-vpn uninstall` removes the service (`PURGE=1` also deletes the accounts). The script is [install.sh](install.sh).

## Getting started

1. Make a free Firefox Account at [accounts.firefox.com](https://accounts.firefox.com), if you have none.
2. Open the app, choose your language and country, and add the account.
3. Tap the button to connect.

For more data, add more accounts: each one brings 50 GB a month.

## Limits

These come from Mozilla's service:

- **TCP only.** UDP does not pass, so apps that use it (some games and calls) fall back to TCP.
- **Web ports only.** Mozilla's proxy connects to ports 80, 443, 8080, and 8443.
- Mozilla locks some locations for some accounts.

## Building from source

```powershell
scripts\build-windows.ps1   # dist\Firefox-VPN-<version>\, its .zip, and the installer
scripts\build-android.ps1   # dist\Firefox-VPN-<version>-android\
```

You need Go and Flutter, and for Android the Android SDK and NDK with gomobile. The project has two parts:

```text
core/   Go: the VPN core (accounts, connections, routing, DNS, the dashboard and its API)
app/    Flutter: the app for Windows, Android, and macOS
```

The app is a client of the core's local API, so every platform shares one core. The developer documentation is in [core/doc](core/doc/README.md).

## License

[MIT](LICENSE).

## Credits

Country flags are from [flag-icons](https://github.com/lipis/flag-icons) (MIT). The Persian font is [Vazirmatn](https://github.com/rastikerdar/vazirmatn) (SIL Open Font License).
