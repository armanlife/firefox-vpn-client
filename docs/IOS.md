# iOS: build, sign, and install

Firefox VPN on iOS is the same Flutter app as the other platforms, with the
same Go core. The VPN is a **packet tunnel provider** — a small system
extension that runs the core and hev-socks5-tunnel (vendored under
`app/ios/PacketTunnel/hev`) on the device's packets, the same way Android's
foreground service does. The app talks to the extension's core over the same
HTTP API on loopback, and both use one data folder in the App Group's
container.

## What the GitHub Action builds

A tag `v<version>` (or "Run workflow" on the Build action) builds
`Firefox-VPN-<version>-iOS-unsigned.ipa`:

- the Go core compiles for iOS with `gomobile bind -target=ios` into
  `app/ios/Core.xcframework`;
- `flutter build ios --release --no-codesign` builds the app **unsigned**;
- the `.app` is zipped into an IPA (`Payload/Runner.app`, with the tunnel's
  `PacketTunnel.appex` inside).

Unsigned means exactly that: no certificate has touched it, so no device
installs it as it is. It becomes installable with **your** signature — no
paid developer account is required, and the app is not on the App Store.

## Signing and installing

The bundle ids are `com.arman.firefoxvpn` (app) and
`com.arman.firefoxvpn.PacketTunnel` (extension), in the App Group
`group.com.arman.firefoxvpn`. When you re-sign with your own name, your
tool rewrites the ids to yours and the entitlements to your team's — give it
the entitlements files the repo carries
(`app/ios/Runner/Runner.entitlements`, `app/ios/PacketTunnel/PacketTunnel.entitlements`),
or let it make its own; both targets need the App Group, and the extension
the packet-tunnel entitlement, or the VPN toggle does nothing.

Any of these works:

- **Sideloadly, AltStore, or ESign** on a computer or another device: point
  them at the IPA, give an Apple ID (7 days) or a developer certificate
  (a year), and install.
- **TrollStore** installs the IPA as it is, signature and all, on the iOS
  versions it covers.
- **Xcode**: open `app/ios/Runner.xcworkspace` with the built
  `Core.xcframework` in place, set your team on both targets, and run.

After the first install: allow the VPN when iOS asks (the first press of the
connect button), add a Firefox Account, and connect. The app offers the
release's new IPA in its own update check, which opens the release page.

## Building it yourself

On a Mac with Xcode, Go, and Flutter (see `.github/workflows/build.yml` for
the exact versions):

```bash
go install golang.org/x/mobile/cmd/gomobile@v0.0.0-20260908204917-8b95e45f8d3e
go install golang.org/x/mobile/cmd/gobind@v0.0.0-20260908204917-8b95e45f8d3e
(cd core && gomobile bind -target=ios -iosversion 15.0 -o ../app/ios/Core.xcframework ./mobile)
cd app && flutter pub get && flutter build ios --release --no-codesign
```

Or run `bash scripts/build-ios.sh`, which does all three steps and leaves
`dist/Firefox-VPN-<version>-iOS-unsigned.ipa`.

## What iOS does differently

- **Per-app routing** (Android's "Bypass selected apps") has no iOS control:
  the VPN carries every app's traffic. The core's site routing (smart
  routing by country) works as everywhere.
- **Proxy-only mode** has no meaning on iOS (there is no system proxy to
  point at other apps), so the mode choice is Android's alone.
- **No Android TV**: the phone layout everywhere, portrait on the phone.
- The tunnel's extension keeps the VPN on with the app gone, as iOS provides;
  when the VPN is off, the app runs the core itself so the accounts and the
  settings work.
