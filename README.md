# Firefox VPN

**Mozilla's free VPN proxy on your whole computer and your phone, with as many accounts as you like.**

[فارسی](README_fa.md)

## What is Firefox VPN?

**Firefox VPN** is a free, open-source VPN client that uses a Firefox Account to carry the internet traffic of **every app on the device** through **Fastly**'s infrastructure, over **HTTP/2 and HTTP/3** tunnels.

Every Firefox Account comes with **50 GB of free traffic a month**. The app supports several accounts and uses their combined allowance, so you are not held to one account's 50 GB.

Firefox VPN is available for **Android, Windows, macOS, and Linux**, completely free, with no ads, and open source.

## Why Firefox VPN

- **Free, from a trusted network.** The traffic goes through Mozilla's own servers (Fastly), the same ones Firefox uses. There is no third-party VPN company in the middle.
- **More data with more accounts.** Add several Firefox Accounts. When the active one has used 90% of its data, the next one takes over by itself, without dropping your connections.
- **Every app, not only the browser.** A real VPN on Android. A system-wide proxy on Windows. A SOCKS5 and HTTP proxy for anything else.
- **Smart traffic routing.** Your own country's sites open directly, without the VPN, so they load faster and use no data.
- **Made for filtered networks.** Encrypted DNS, HTTP/2 and HTTP/3 (QUIC) support, a check that detects tampered DNS, and an optional relay of your own for when signing in to Mozilla is blocked.
- **Small and light.** About 14 MB for Android and 18 MB for Windows. No ads, no tracking, and no server involved but Mozilla's.

## Features

### Connection

- One tap to connect. The app always starts disconnected and connects only when you ask.
- Locations from Mozilla's server list, each with its flag and real delay. Choose one yourself, or let the app pick the recommended or the fastest.
- HTTP/2 and HTTP/3 (QUIC) support.
- Pauses the connection to Mozilla when nothing uses it, so the accounts rest. The next request wakes it in a few seconds.
- Waits quietly while there is no network, and reconnects at once on a new one.
- A connection test with every stage timed, and the public IP address, country, and network that websites see.

### Accounts

- Sign in with a Firefox Account inside the app, with every step Mozilla may ask for: an email code, an authenticator code, or an image check.
- The data left on each account, and the date it resets.
- Automatic switching between accounts at a share you choose.
- A reminder when the active account runs low and no other is ready.
- Expired sign-ins are renewed by themselves, with the password stored on your device.

### Smart traffic routing

- Sites and addresses of your country open directly, without the VPN: Iran, China, Russia, Afghanistan, Turkey, Indonesia, or Brazil.
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
- The speed and the location in the notification.

### Windows

- A proxy for the whole system, or only for the apps you set up.
- Lives in the tray and, if you like, starts with Windows.
- Share the proxy with other devices on your network, protected with a login.

### macOS

- The same app in the menu bar, with the system proxy for every network (Wi-Fi, Ethernet), and starting at sign-in.
- One file for Apple silicon and Intel Macs.

### Linux

- The same app, with the system proxy (GNOME's setting), the tray, and starting at sign-in, installed with [one command](#install-and-update-to-the-latest-version-on-linuxmacos).
- For servers, a headless core as a systemd service, also with one command.
- A web dashboard to manage everything from a browser: status, accounts, locations, settings, and logs.

### For everyone

- 15 languages: English, فارسی, 简体中文, 繁體中文, Русский, Türkçe, العربية, Azərbaycan, Bahasa Indonesia, Español, Français, Magyar, Português, Tiếng Việt, and বাংলা. Persian and Arabic read right to left.
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

### Install and update to the latest version on Linux/macOS

Windows and Android users don't need this: take the installer from the table above.

```bash
curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | bash
```

- **macOS:** the app, in Applications.
- **Linux with a desktop:** the app, for you (no sudo), in the applications menu.
- **Linux without a desktop (a server):** the core as a systemd service with the web dashboard; sudo asks for your password.
- **An SSH session:** it could be a server or a desktop computer reached remotely, so the script asks.

When Firefox VPN is already installed, the same command asks whether to update it (the default: press Enter) or remove it, and on removal whether to delete the accounts and settings too. Every download is checked against the release's checksums. For scripts, an argument skips the questions: `desktop`, `server`, `remove-desktop`, or `remove-server` (for example `... | bash -s -- server`).

### Web dashboard

The web dashboard is for **Linux servers without a desktop (CLI)**, where the app cannot run; on Windows, macOS, Android, and Linux desktops, use the app. It is built into the core, opens in any browser, and does everything the app does: accounts and their remaining data, server choice and real-delay tests, the connection test and public IP, the live log, and every setting.

- **Address:** http://127.0.0.1:10820
- **Proxy:** SOCKS5 and HTTP on `127.0.0.1:10810`; point apps or other devices at it.
- **Reaching a server's dashboard from your computer:** it listens on the server itself only, which is the safest default. Open it through an SSH tunnel, then browse to http://127.0.0.1:10820 on your computer:

```bash
ssh -L 10820:127.0.0.1:10820 user@your-server
```

Service commands on the server:

```bash
sudo firefox-vpn add-account           # sign in to a Firefox Account (also possible in the web dashboard)
sudo firefox-vpn status                # the service and its state
sudo firefox-vpn logs                  # follow the service's log
sudo firefox-vpn restart               # restart the service
sudo firefox-vpn set-dashboard-login   # set the web dashboard's username and password
```
