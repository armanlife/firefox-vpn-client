#!/usr/bin/env bash
# Installs firefox-vpn-core as a systemd service on Linux.
#
# The program and its data folder live together in INSTALL_DIR (portable
# layout): INSTALL_DIR/firefox-vpn-core and INSTALL_DIR/user-data. Settings and
# accounts are managed from the web dashboard (default 127.0.0.1:10820) or
# with the subcommands below.
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-firefox-vpn}"
SERVICE_USER="${SERVICE_USER:-firefox-vpn}"
INSTALL_DIR="${INSTALL_DIR:-/opt/firefox-vpn}"
BINARY="${BINARY:-}"
PURGE="${PURGE:-0}"
UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
BIN_PATH="$INSTALL_DIR/firefox-vpn-core"
DATA_DIR="$INSTALL_DIR/user-data"

# The previous (flag-based) installation, migrated on install.

log() { printf '[%s] %s\n' "$SERVICE_NAME" "$*"; }
die() { printf '[%s] error: %s\n' "$SERVICE_NAME" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: sudo $0 <command>

Commands:
  install              Install or update the binary and the service, then start it
  uninstall            Stop and remove the service (PURGE=1 also deletes $INSTALL_DIR)
  status               Show the service state and the runtime status file
  logs                 Follow the service log
  restart              Restart the service
  add-account          Sign in to a Firefox Account on this terminal
  list-accounts        List accounts, status, and quota
  set-dashboard-login  Set or remove the dashboard username and password

Environment:
  BINARY=path          Install this prebuilt binary instead of building from the source tree
  INSTALL_DIR=dir      Program and data folder (default /opt/firefox-vpn)
  SERVICE_NAME, SERVICE_USER

The dashboard listens on 127.0.0.1:10820. From another machine, use an SSH
tunnel (ssh -L 10820:127.0.0.1:10820 host), or run set-dashboard-login and set
dashboard.listen to 0.0.0.0:10820 in $DATA_DIR/config.json, then restart.
EOF
}

need_root() { [ "$(id -u)" -eq 0 ] || die "run this command with sudo"; }

repo_root() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

build_binary() {
  local out="$1"
  if [ -n "$BINARY" ]; then
    [ -f "$BINARY" ] || die "BINARY=$BINARY does not exist"
    cp "$BINARY" "$out"
    return
  fi
  command -v go >/dev/null 2>&1 || die "Go is not installed; install Go or pass BINARY=path/to/firefox-vpn-core"
  log "building from $(repo_root)"
  (cd "$(repo_root)" && CGO_ENABLED=0 go build -trimpath -o "$out" ./cmd/firefox-vpn-core)
}

ensure_user() {
  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    log "creating system user $SERVICE_USER"
    useradd --system --home-dir "$DATA_DIR" --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
  fi
}


write_unit() {
  cat >"$UNIT_FILE" <<EOF
[Unit]
Description=Firefox VPN SOCKS5 proxy and dashboard
After=network-online.target
Wants=network-online.target

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN_PATH
Restart=on-failure
RestartSec=10
UMask=0077
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$DATA_DIR

[Install]
WantedBy=multi-user.target
EOF
}

run_as_service_user() {
  [ -x "$BIN_PATH" ] || die "not installed; run: sudo $0 install"
  runuser -u "$SERVICE_USER" -- "$BIN_PATH" "$@"
}

cmd_install() {
  need_root
  command -v systemctl >/dev/null 2>&1 || die "systemd is required"
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  build_binary "$tmp"
  ensure_user
  install -d -m 0755 -o root -g root "$INSTALL_DIR"
  install -d -m 0700 -o "$SERVICE_USER" -g "$SERVICE_USER" "$DATA_DIR"
  install -m 0755 -o root -g root "$tmp" "$BIN_PATH"
  write_unit
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service" >/dev/null
  systemctl restart "${SERVICE_NAME}.service"
  log "installed $BIN_PATH; data in $DATA_DIR"
  log "dashboard: http://127.0.0.1:10820 (add accounts there, or: sudo $0 add-account)"
}

cmd_uninstall() {
  need_root
  systemctl disable --now "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  rm -f "$UNIT_FILE"
  systemctl daemon-reload
  if [ "$PURGE" = "1" ]; then
    log "deleting $INSTALL_DIR including accounts and settings"
    rm -rf "$INSTALL_DIR"
    userdel "$SERVICE_USER" >/dev/null 2>&1 || true
  else
    log "service removed; $INSTALL_DIR kept (PURGE=1 deletes it)"
  fi
}

cmd_status() {
  systemctl --no-pager status "${SERVICE_NAME}.service" || true
  if [ -r "$DATA_DIR/status.json" ]; then
    echo
    cat "$DATA_DIR/status.json"
  fi
}

case "${1:-}" in
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
  logs) journalctl -u "${SERVICE_NAME}.service" -f ;;
  restart) need_root; systemctl restart "${SERVICE_NAME}.service" ;;
  add-account) need_root; run_as_service_user -add-account && systemctl restart "${SERVICE_NAME}.service" ;;
  list-accounts) need_root; run_as_service_user -list-accounts ;;
  set-dashboard-login) need_root; run_as_service_user -set-dashboard-login && systemctl restart "${SERVICE_NAME}.service" ;;
  -h|--help|help|"") usage ;;
  *) usage; exit 2 ;;
esac
