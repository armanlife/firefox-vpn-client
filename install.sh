#!/usr/bin/env bash
# Installs or updates Firefox VPN on Linux from the newest release on GitHub.
#
# The desktop app, for the current user (no sudo):
#
#   curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | bash -s -- desktop
#
# The core alone, as a systemd service (servers):
#
#   curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | sudo bash
#
# Running it again updates; accounts and settings stay. "remove-desktop"
# removes the desktop app (PURGE=1 also deletes its accounts); the service
# is removed with "sudo firefox-vpn uninstall".
#
# Environment:
#   VERSION=v1.1.1   a given release instead of the newest
#   BASE_URL=url     a mirror that serves the release files
#   INSTALL_DIR, SERVICE_NAME, SERVICE_USER: the service's, as in
#   core/scripts/install-systemd.sh
set -euo pipefail

REPO="armanlife/firefox-vpn-client"
RAW="https://raw.githubusercontent.com/$REPO/main/install.sh"
VERSION="${VERSION:-latest}"
if [ "$VERSION" = "latest" ]; then
  BASE_URL="${BASE_URL:-https://github.com/$REPO/releases/latest/download}"
else
  BASE_URL="${BASE_URL:-https://github.com/$REPO/releases/download/$VERSION}"
fi
COMMAND=/usr/local/bin/firefox-vpn

# The desktop app's places, for the current user.
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$HOME/.local/opt/firefox-vpn-client"
DESKTOP_FILE="$DATA_HOME/applications/com.arman.firefoxvpn.desktop"
AUTOSTART_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/firefox-vpn-client.desktop"
APP_DATA="$DATA_HOME/firefox-vpn-client"

log() { printf '[firefox-vpn] %s\n' "$*"; }
die() { printf '[firefox-vpn] error: %s\n' "$*" >&2; exit 1; }

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "curl or wget is required"
  fi
}

# download <archive> <folder>: the release file, checked against the
# release's checksums when it has them, unpacked into <folder>.
download() {
  local archive="$1" into="$2"
  log "downloading $archive ($VERSION)"
  fetch "$BASE_URL/$archive" "$into/$archive" || die "could not download $BASE_URL/$archive"
  if fetch "$BASE_URL/SHA256SUMS.txt" "$into/SHA256SUMS.txt" 2>/dev/null; then
    local line
    line="$(awk -v f="$archive" '{ n = $2; sub(/^\*/, "", n) } n == f' "$into/SHA256SUMS.txt")"
    [ -n "$line" ] || die "$archive is missing from SHA256SUMS.txt"
    (cd "$into" && printf '%s\n' "$line" | sha256sum -c --quiet -) || die "$archive does not match its checksum"
  else
    log "no SHA256SUMS.txt in the release; skipping the checksum"
  fi
  tar -xzf "$into/$archive" -C "$into"
}

install_server() {
  [ "$(id -u)" -eq 0 ] || die "run it with sudo: curl -fsSL $RAW | sudo bash"
  command -v systemctl >/dev/null 2>&1 || die "systemd is required"
  local arch
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) die "no build for $(uname -m); the core builds from source: core/scripts/install-systemd.sh" ;;
  esac
  local dir="$tmp/firefox-vpn-core-linux-$arch"
  download "firefox-vpn-core-linux-$arch.tar.gz" "$tmp"
  [ -f "$dir/firefox-vpn-core" ] && [ -f "$dir/install-systemd.sh" ] || die "not a firefox-vpn-core archive"

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
}

install_desktop() {
  [ "$(id -u)" -ne 0 ] || die "install the desktop app as yourself, without sudo: curl -fsSL $RAW | bash -s -- desktop"
  case "$(uname -m)" in
    x86_64 | amd64) ;;
    *) die "the desktop app is built for x64 only; on $(uname -m), install the core: curl -fsSL $RAW | sudo bash" ;;
  esac
  download "Firefox-VPN-Linux-x64.tar.gz" "$tmp"
  [ -f "$tmp/firefox-vpn/firefox-vpn" ] || die "not a Firefox VPN archive"
  chmod 0755 "$tmp/firefox-vpn/firefox-vpn" "$tmp/firefox-vpn/firefox-vpn-core"

  # A running copy keeps its open files; the new one replaces the folder.
  mkdir -p "$(dirname "$APP_DIR")"
  rm -rf "$APP_DIR.old"
  if [ -d "$APP_DIR" ]; then mv "$APP_DIR" "$APP_DIR.old"; fi
  mv "$tmp/firefox-vpn" "$APP_DIR"
  rm -rf "$APP_DIR.old"

  mkdir -p "$(dirname "$DESKTOP_FILE")"
  cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Firefox VPN
Comment=Mozilla's VPN servers through your Firefox Accounts
Exec="$APP_DIR/firefox-vpn"
Icon=$APP_DIR/data/app_icon.png
Terminal=false
Categories=Network;
StartupWMClass=com.arman.firefoxvpn
EOF
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "$(dirname "$DESKTOP_FILE")" || true
  fi

  log "installed in $APP_DIR"
  if ! { ldconfig -p 2>/dev/null | grep -qE 'lib(ayatana-)?appindicator3\.so'; }; then
    log "no tray icon library: install libayatana-appindicator3-1 (Debian, Ubuntu) or libappindicator-gtk3 (Fedora, Arch) for the tray icon"
  fi
  cat <<EOF

Firefox VPN is installed. Open it from the applications menu, or run:
  $APP_DIR/firefox-vpn
Update:  run the same install command again
Remove:  curl -fsSL $RAW | bash -s -- remove-desktop
EOF
}

remove_desktop() {
  rm -rf "$APP_DIR" "$APP_DIR.old"
  rm -f "$DESKTOP_FILE" "$AUTOSTART_FILE"
  if [ "${PURGE:-0}" = "1" ]; then
    rm -rf "$APP_DATA"
    log "removed the app, its accounts, and its settings"
  else
    log "removed the app; accounts and settings stay in $APP_DATA (PURGE=1 deletes them)"
  fi
}

[ "$(uname -s)" = "Linux" ] || die "this installer is for Linux"
command -v tar >/dev/null 2>&1 || die "tar is required"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

case "${1:-server}" in
  server) install_server ;;
  desktop) install_desktop ;;
  remove-desktop) remove_desktop ;;
  *) die "unknown command ${1}; use desktop, server, or remove-desktop" ;;
esac
