#!/usr/bin/env bash
# Builds the Linux desktop app with its core into
# dist/Firefox-VPN-<version>-Linux-x64.tar.gz: a firefox-vpn folder with
# firefox-vpn (the Flutter app), firefox-vpn-core (the Go core, which the
# app starts with -app), and Flutter's lib/ and data/. "install.sh desktop"
# installs it for the current user. The version is "major.minor.patch" from
# app/pubspec.yaml.
#
# Needs Flutter, GTK 3 headers, clang, cmake, ninja, and pkg-config
# (Ubuntu: clang cmake ninja-build pkg-config libgtk-3-dev), and Go for the
# core, unless CORE names a firefox-vpn-core built for linux/amd64 already.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$root/app/pubspec.yaml")"
[ -n "$version" ] || { echo "no version in app/pubspec.yaml" >&2; exit 1; }

(cd "$root/app" && flutter pub get && flutter build linux --release --no-pub --dart-define=APP_VERSION="$version")

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
app="$stage/firefox-vpn"
cp -r "$root/app/build/linux/x64/release/bundle" "$app"
if [ -n "${CORE:-}" ]; then
  install -m 0755 "$CORE" "$app/firefox-vpn-core"
else
  (cd "$root/core" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
    -ldflags "-s -w -X github.com/armanlife/firefox-vpn-client/core/internal/version.Current=$version" \
    -o "$app/firefox-vpn-core" ./cmd/firefox-vpn-core)
fi
install -m 0644 "$root/LICENSE" "$app/LICENSE"

mkdir -p "$root/dist"
out="$root/dist/Firefox-VPN-$version-Linux-x64.tar.gz"
tar -czf "$out" -C "$stage" --owner=0 --group=0 firefox-vpn
echo "Built $out ($(du -h "$out" | cut -f1))"
