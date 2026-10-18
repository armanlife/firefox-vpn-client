#!/usr/bin/env bash
# Installs or updates Firefox VPN from the newest release on GitHub.
#
# The app on macOS, or on a Linux desktop, for the current user (no sudo):
#
#   curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | bash -s -- desktop
#
# The core alone, as a systemd service (Linux servers):
#
#   curl -fsSL https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh | sudo bash
#
# Running it again updates; accounts and settings stay. "remove-desktop"
# removes the app (PURGE=1 also deletes its accounts); the service is
# removed with "sudo firefox-vpn uninstall". On macOS "desktop" is the
# default.
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
OS="$(uname -s)"

# The Linux app's places, for the current user.
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$HOME/.local/opt/firefox-vpn-client"
DESKTOP_FILE="$DATA_HOME/applications/com.arman.firefoxvpn.desktop"
AUTOSTART_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/firefox-vpn-client.desktop"
APP_DATA="$DATA_HOME/firefox-vpn-client"

# The macOS app's.
MAC_APP="Firefox VPN.app"
MAC_AGENT="$HOME/Library/LaunchAgents/com.arman.firefoxvpn.plist"
MAC_DATA="$HOME/Library/Application Support/Firefox VPN Client"

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

sha256_check() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c --quiet -
  else
    shasum -a 256 -c --quiet -
  fi
}

# download <file>: the release file into $tmp, checked against the release's
# checksums when it has them.
download() {
  local file="$1"
  log "downloading $file ($VERSION)"
  fetch "$BASE_URL/$file" "$tmp/$file" || die "could not download $BASE_URL/$file"
  if fetch "$BASE_URL/SHA256SUMS.txt" "$tmp/SHA256SUMS.txt" 2>/dev/null; then
    local line
    line="$(awk -v f="$file" '{ n = $2; sub(/^\*/, "", n) } n == f' "$tmp/SHA256SUMS.txt")"
    [ -n "$line" ] || die "$file is missing from SHA256SUMS.txt"
    (cd "$tmp" && printf '%s\n' "$line" | sha256_check) || die "$file does not match its checksum"
  else
    log "no SHA256SUMS.txt in the release; skipping the checksum"
  fi
}

# The Go and file name of this machine's processor.
arch() {
  case "$(uname -m)" in
    x86_64 | amd64) echo amd64 ;;
    aarch64 | arm64) echo arm64 ;;
    *) die "no build for $(uname -m)" ;;
  esac
}

install_server() {
  [ "$OS" = "Linux" ] || die "the service is for Linux; on macOS, install the app: curl -fsSL $RAW | bash"
  [ "$(id -u)" -eq 0 ] || die "run it with sudo: curl -fsSL $RAW | sudo bash"
  command -v systemctl >/dev/null 2>&1 || die "systemd is required"
  local name dir
  name="firefox-vpn-core-linux-$(arch)"
  dir="$tmp/$name"
  download "$name.tar.gz"
  tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
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

install_linux_app() {
  local file
  file="Firefox-VPN-Linux-$(arch).tar.gz"
  download "$file"
  tar -xzf "$tmp/$file" -C "$tmp"
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

# macOS: the app into /Applications (or ~/Applications when that is not
# writable). Downloaded this way it carries no quarantine flag, so macOS
# opens it without asking.
install_mac_app() {
  local file="Firefox-VPN-macOS.dmg" dest=/Applications
  [ -w "$dest" ] || dest="$HOME/Applications"
  mkdir -p "$dest"
  download "$file"
  mkdir "$tmp/mnt"
  hdiutil attach -nobrowse -readonly -quiet -mountpoint "$tmp/mnt" "$tmp/$file" || die "could not open $file"
  mounted="$tmp/mnt"
  [ -d "$tmp/mnt/$MAC_APP" ] || die "not a Firefox VPN disk image"
  # A running copy quits first, so the new one replaces it.
  osascript -e 'quit app "Firefox VPN"' >/dev/null 2>&1 || true
  rm -rf "$dest/$MAC_APP"
  ditto "$tmp/mnt/$MAC_APP" "$dest/$MAC_APP"
  hdiutil detach -quiet "$tmp/mnt" || true
  mounted=""
  log "installed in $dest/$MAC_APP"
  cat <<EOF

Firefox VPN is installed. Open it from Launchpad or Applications, or run:
  open "$dest/$MAC_APP"
Update:  run the same install command again
Remove:  curl -fsSL $RAW | bash -s -- remove-desktop
EOF
}

install_desktop() {
  [ "$(id -u)" -ne 0 ] || die "install the app as yourself, without sudo: curl -fsSL $RAW | bash -s -- desktop"
  case "$OS" in
    Darwin) install_mac_app ;;
    *) install_linux_app ;;
  esac
}

remove_desktop() {
  local data
  if [ "$OS" = "Darwin" ]; then
    osascript -e 'quit app "Firefox VPN"' >/dev/null 2>&1 || true
    rm -rf "/Applications/$MAC_APP" "$HOME/Applications/$MAC_APP"
    rm -f "$MAC_AGENT"
    data="$MAC_DATA"
  else
    rm -rf "$APP_DIR" "$APP_DIR.old"
    rm -f "$DESKTOP_FILE" "$AUTOSTART_FILE"
    data="$APP_DATA"
  fi
  if [ "${PURGE:-0}" = "1" ]; then
    rm -rf "$data"
    log "removed the app, its accounts, and its settings"
  else
    log "removed the app; accounts and settings stay in $data (PURGE=1 deletes them)"
  fi
}

case "$OS" in
  Linux) default=server ;;
  Darwin) default=desktop ;;
  *) die "this installer is for Linux and macOS" ;;
esac
command -v tar >/dev/null 2>&1 || die "tar is required"
tmp="$(mktemp -d)"
mounted=""
cleanup() {
  if [ -n "$mounted" ]; then hdiutil detach -quiet "$mounted" || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT

case "${1:-$default}" in
  server) install_server ;;
  desktop) install_desktop ;;
  remove-desktop) remove_desktop ;;
  *) die "unknown command ${1}; use desktop, server, or remove-desktop" ;;
esac
