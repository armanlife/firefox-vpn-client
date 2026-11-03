#!/usr/bin/env bash
# Builds the iOS app the way the workflow (.github/workflows/build.yml, the
# ios job) does, on a Mac with Xcode, Go, and Flutter:
# the Go core as Core.xcframework, then the unsigned IPA.
#
#   bash scripts/build-ios.sh
#
# dist/Firefox-VPN-<version>-iOS-unsigned.ipa is the result; sign it with
# your certificate (docs/IOS.md).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^version:[[:space:]]*\([0-9.]*\).*/\1/p' "$root/app/pubspec.yaml")"
gopath="$(go env GOPATH)"
gomobile="$gopath/bin/gomobile"

command -v go >/dev/null || { echo "go is not in the PATH"; exit 1; }
command -v flutter >/dev/null || { echo "flutter is not in the PATH"; exit 1; }
[ -x "$gomobile" ] || go install golang.org/x/mobile/cmd/gomobile@v0.0.0-20260908204917-8b95e45f8d3e
go install golang.org/x/mobile/cmd/gobind@v0.0.0-20260908204917-8b95e45f8d3e

echo "== the core (gomobile bind -target=ios) =="
(cd "$root/core" && "$gomobile" bind -target=ios -iosversion 15.0 -trimpath \
  -ldflags "-s -w -X github.com/astwdnya/firefox-vpn-client/core/internal/version.Current=$version" \
  -o "$root/app/ios/Core.xcframework" ./mobile)

echo "== the app (flutter build ios --release --no-codesign) =="
(cd "$root/app" && flutter pub get && flutter build ios --release --no-codesign --dart-define=APP_VERSION="$version")

mkdir -p "$root/dist/Payload"
rm -rf "$root/dist/Payload"
cp -R "$root/app/build/ios/iphoneos/Runner.app" "$root/dist/Payload/"
(cd "$root/dist" && zip -qry "Firefox-VPN-$version-iOS-unsigned.ipa" Payload && rm -rf Payload)

echo "dist/Firefox-VPN-$version-iOS-unsigned.ipa"
