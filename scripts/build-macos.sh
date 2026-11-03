#!/usr/bin/env bash
# Builds the macOS app with its core into dist/Firefox-VPN-<version>-macOS.dmg:
# "Firefox VPN.app" (Apple silicon and Intel), with firefox-vpn-core (the Go
# core, which the app starts with -app) and firefox-vpn-tun (the TUN mode's
# service, which the app installs as a launchd daemon the first time the
# mode is chosen) beside the app's executable in Contents/MacOS, and a link
# to Applications to drag it to. The same app goes alone into
# dist/Firefox-VPN-<version>-macOS.tar.gz, which the app downloads to update
# itself (core/internal/update). The version is "major.minor.patch" from
# app/pubspec.yaml.
#
# Updates must be signed (Ed25519): with a signing key
# (FIREFOX_VPN_SIGNING_KEY, CI's secret, or the file named by
# FIREFOX_VPN_SIGNING_KEY_FILE), the core installs only releases whose
# SHA256SUMS.txt is signed with it, an installed TUN service accepts updates
# signed with it, and Contents/Resources/firefox-vpn-tun.sig holds the
# bundled one's. Without one the app's updates are downloaded by hand, and
# the TUN service takes no updates: a newer one is installed again, with the
# administrator prompt.
#
# The app is signed ad hoc (no Apple Developer ID), which Apple silicon
# needs to run it at all; macOS asks once before opening a downloaded copy.
# Needs Flutter, Xcode, and Go.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$root/app/pubspec.yaml")"
[ -n "$version" ] || { echo "no version in app/pubspec.yaml" >&2; exit 1; }
module=github.com/astwdnya/firefox-vpn-client/core

public=""
if [ -n "${FIREFOX_VPN_SIGNING_KEY:-}${FIREFOX_VPN_SIGNING_KEY_FILE:-}" ]; then
  public="$(cd "$root/core" && go run ./tools/sign -public)"
else
  echo "warning: no signing key (FIREFOX_VPN_SIGNING_KEY or FIREFOX_VPN_SIGNING_KEY_FILE): this build installs no updates" >&2
fi
goflags="-s -w -X $module/internal/version.Current=$version"
[ -z "$public" ] || goflags="$goflags -X $module/internal/signing.Key=$public"

(cd "$root/app" && flutter pub get && flutter build macos --release --no-pub --dart-define=APP_VERSION="$version")

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
app="$stage/Firefox VPN.app"
cp -R "$root/app/build/macos/Build/Products/Release/Firefox VPN.app" "$app"

# The core and the TUN service for both processors, one file each.
for arch in arm64 amd64; do
  (cd "$root/core" && CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" go build -trimpath \
    -ldflags "$goflags" -o "$stage/core-$arch" ./cmd/firefox-vpn-core)
  (cd "$root/core" && CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" go build -tags with_gvisor -trimpath \
    -ldflags "$goflags" -o "$stage/tun-$arch" ./cmd/firefox-vpn-tun)
done
core="$app/Contents/MacOS/firefox-vpn-core"
tun="$app/Contents/MacOS/firefox-vpn-tun"
lipo -create -output "$core" "$stage/core-arm64" "$stage/core-amd64"
lipo -create -output "$tun" "$stage/tun-arm64" "$stage/tun-amd64"

# The programs inside the bundle change it: sign them, then the whole app.
codesign --force --sign - "$core"
codesign --force --sign - "$tun"
codesign --force --deep --sign - "$app"
# The TUN service's update signature is of its executable as signed, and
# goes to Contents/Resources (only code may be in Contents/MacOS); the app
# is then sealed again without --deep, which leaves the executable as it is.
if [ -n "$public" ]; then
  (cd "$root/core" && go run ./tools/sign "$tun")
  mv "$tun.sig" "$app/Contents/Resources/firefox-vpn-tun.sig"
  signed="$(shasum -a 256 "$tun")"
  codesign --force --sign - "$app"
  [ "$(shasum -a 256 "$tun")" = "$signed" ] || { echo "sealing the app changed firefox-vpn-tun" >&2; exit 1; }
fi
codesign --verify --deep --strict "$app"

# The app alone for its updates: tar keeps the frameworks' links; without
# extended attributes or AppleDouble files (._*), which would lie in the
# bundle unsealed.
mkdir -p "$root/dist"
archive="$root/dist/Firefox-VPN-$version-macOS.tar.gz"
COPYFILE_DISABLE=1 tar --no-mac-metadata -czf "$archive" -C "$stage" "Firefox VPN.app"

dmg="$stage/dmg"
mkdir "$dmg"
mv "$app" "$dmg/"
ln -s /Applications "$dmg/Applications"
out="$root/dist/Firefox-VPN-$version-macOS.dmg"
rm -f "$out"
hdiutil create -volname "Firefox VPN" -srcfolder "$dmg" -ov -format UDZO "$out" >/dev/null
echo "Built $out ($(du -h "$out" | cut -f1)) and $archive ($(du -h "$archive" | cut -f1))"
