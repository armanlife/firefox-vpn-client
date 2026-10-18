#!/usr/bin/env bash
# Installs or updates the Firefox VPN core on Linux as a systemd service,
# from the newest release on GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | sudo bash
#
# Running it again updates the core; accounts and settings stay. After that,
# the "firefox-vpn" command manages the service (sudo firefox-vpn help).
#
# Environment:
#   VERSION=v1.1.1   a given release instead of the newest
#   BASE_URL=url     a mirror that serves the release files
#   INSTALL_DIR, SERVICE_NAME, SERVICE_USER: as in core/scripts/install-systemd.sh
set -euo pipefail

REPO="armanlife/firefox-vpn-client"
VERSION="${VERSION:-latest}"
if [ "$VERSION" = "latest" ]; then
  BASE_URL="${BASE_URL:-https://github.com/$REPO/releases/latest/download}"
else
  BASE_URL="${BASE_URL:-https://github.com/$REPO/releases/download/$VERSION}"
fi
COMMAND=/usr/local/bin/firefox-vpn

log() { printf '[firefox-vpn] %s\n' "$*"; }
die() { printf '[firefox-vpn] error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Linux" ] || die "this installer is for Linux"
[ "$(id -u)" -eq 0 ] || die "run it with sudo: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | sudo bash"
command -v systemctl >/dev/null 2>&1 || die "systemd is required"
command -v tar >/dev/null 2>&1 || die "tar is required"

case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) die "no build for $(uname -m); the core builds from source: core/scripts/install-systemd.sh" ;;
esac
archive="firefox-vpn-core-linux-$arch.tar.gz"

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "curl or wget is required"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log "downloading $archive ($VERSION)"
fetch "$BASE_URL/$archive" "$tmp/$archive" || die "could not download $BASE_URL/$archive"

# The release's checksums, when it has them.
if fetch "$BASE_URL/SHA256SUMS.txt" "$tmp/SHA256SUMS.txt" 2>/dev/null; then
  line="$(awk -v f="$archive" '{ n = $2; sub(/^\*/, "", n) } n == f' "$tmp/SHA256SUMS.txt")"
  [ -n "$line" ] || die "$archive is missing from SHA256SUMS.txt"
  (cd "$tmp" && printf '%s\n' "$line" | sha256sum -c --quiet -) || die "$archive does not match its checksum"
else
  log "no SHA256SUMS.txt in the release; skipping the checksum"
fi

tar -xzf "$tmp/$archive" -C "$tmp"
dir="$tmp/firefox-vpn-core-linux-$arch"
[ -f "$dir/firefox-vpn-core" ] && [ -f "$dir/install-systemd.sh" ] || die "$archive is not a firefox-vpn-core archive"

SELF=firefox-vpn BINARY="$dir/firefox-vpn-core" bash "$dir/install-systemd.sh" install
install -m 0755 "$dir/install-systemd.sh" "$COMMAND"

cat <<EOF

Firefox VPN is installed and running.
  Add an account:   sudo firefox-vpn add-account
  Dashboard:        http://127.0.0.1:10820
  Proxy:            SOCKS5 and HTTP on 127.0.0.1:10810 once an account is added
  More commands:    sudo firefox-vpn help
  Update:           run the same install command again
EOF
