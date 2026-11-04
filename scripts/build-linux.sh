#!/usr/bin/env bash
# Builds the Linux desktop app with its core, for this machine's processor
# (amd64 or arm64), into dist/Arman-VPN-<version>-Linux-<arch>.tar.gz: a
# arman-vpn folder with arman-vpn (the Flutter app), core/arman-vpn-core
# (the Go core, which the app starts with -app), core/arman-vpn-tun (the
# TUN mode's service, which the app installs as a systemd service the first
# time the mode is chosen), and Flutter's lib/ and data/. "install.sh
# desktop" installs it for the current user. The version is
# "major.minor.patch" from app/pubspec.yaml.
#
# Updates must be signed (Ed25519): with a signing key
# (ARMAN_VPN_SIGNING_KEY, CI's secret, or the file named by
# ARMAN_VPN_SIGNING_KEY_FILE), the core installs only releases whose
# SHA256SUMS.txt is signed with it, an installed TUN service accepts updates
# signed with it, and core/arman-vpn-tun.sig is written beside it. Without
# one the app's updates are downloaded by hand, and the TUN service takes no
# updates: a newer one is installed again, with the administrator prompt.
#
# Needs Flutter, GTK 3 headers, clang, cmake, ninja, and pkg-config
# (Ubuntu: clang cmake ninja-build pkg-config libgtk-3-dev), and Go (for
# the TUN service, and for the core unless CORE names an arman-vpn-core
# built for this processor).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$root/app/pubspec.yaml")"
[ -n "$version" ] || { echo "no version in app/pubspec.yaml" >&2; exit 1; }
# Flutter's name for the processor, and Go's (also the file's).
case "$(uname -m)" in
  x86_64 | amd64) flutter_arch=x64 arch=amd64 ;;
  aarch64 | arm64) flutter_arch=arm64 arch=arm64 ;;
  *) echo "no Flutter build for $(uname -m)" >&2; exit 1 ;;
esac
module=github.com/armanlife/arman-vpn-client/core

public=""
if [ -n "${ARMAN_VPN_SIGNING_KEY:-}${ARMAN_VPN_SIGNING_KEY_FILE:-}" ]; then
  public="$(cd "$root/core" && go run ./tools/sign -public)"
else
  echo "warning: no signing key (ARMAN_VPN_SIGNING_KEY or ARMAN_VPN_SIGNING_KEY_FILE): this build installs no updates" >&2
fi
goflags="-s -w -X $module/internal/version.Current=$version"
[ -z "$public" ] || goflags="$goflags -X $module/internal/signing.Key=$public"

(cd "$root/app" && flutter pub get && flutter build linux --release --no-pub --dart-define=APP_VERSION="$version")

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
app="$stage/arman-vpn"
cp -r "$root/app/build/linux/$flutter_arch/release/bundle" "$app"
if [ -n "${CORE:-}" ]; then
  install -D -m 0755 "$CORE" "$app/core/arman-vpn-core"
else
  (cd "$root/core" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -trimpath \
    -ldflags "$goflags" -o "$app/core/arman-vpn-core" ./cmd/arman-vpn-core)
fi
(cd "$root/core" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -tags with_gvisor -trimpath \
  -ldflags "$goflags" -o "$app/core/arman-vpn-tun" ./cmd/arman-vpn-tun)
[ -z "$public" ] || (cd "$root/core" && go run ./tools/sign "$app/core/arman-vpn-tun")
install -m 0644 "$root/LICENSE" "$app/LICENSE"
# Links under the app's and the core's names before 1.0.9, which the update
# of those versions checks for and starts; the app removes them
# (core/internal/update/legacy_linux.go).
ln -s arman-vpn "$app/firefox-vpn"
ln -s arman-vpn-core "$app/core/firefox-vpn-core"

mkdir -p "$root/dist"
out="$root/dist/Arman-VPN-$version-Linux-$arch.tar.gz"
tar -czf "$out" -C "$stage" --owner=0 --group=0 arman-vpn
echo "Built $out ($(du -h "$out" | cut -f1))"
