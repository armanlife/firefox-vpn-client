#!/usr/bin/env bash
# Tries the macOS app's own update end to end, on CI's Mac (GitHub
# Actions), as a user's copy goes through it: the app that
# scripts/build-macos.sh built (its tar.gz in dist/) goes to /Applications
# as version <v> and updates itself to <v+1> from a test release on
# loopback (FIREFOX_VPN_UPDATE_SERVER). The app finds the release through
# updates.json a minute after it starts, its core downloads it in the
# background, the next start (by the app's LaunchAgent, as at sign-in)
# installs it, and the new version opens through Launch Services, in the
# menu bar, and says so. Both versions' cores trust a key made for the
# test, which signs the test release. It uses the app's own data folder and
# LaunchAgent, so it runs on CI only. Screenshots and logs go to $1
# (default dist/update-test).
set -euo pipefail

[ "${GITHUB_ACTIONS:-}" = true ] || {
  echo "this replaces the app and its data in your account: it runs on CI's Mac only" >&2
  exit 1
}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$root/app/pubspec.yaml")"
next="${version%.*}.$((${version##*.} + 1))"
module=github.com/astwdnya/firefox-vpn-client/core
out="${1:-$root/dist/update-test}"
app="/Applications/Firefox VPN.app"
data="$HOME/Library/Application Support/Firefox VPN Client"
server="http://127.0.0.1:18080"
work="$(mktemp -d)"
mkdir -p "$out"
[ ! -e "$app" ] || { echo "$app is there already" >&2; exit 1; }

# The app's LaunchAgent, as the app writes it for starting at sign-in
# (app/macos/Runner/MainFlutterWindow.swift).
label=com.arman.firefoxvpn
agent="$HOME/Library/LaunchAgents/$label.plist"

server_pid=""
finish() {
  screencapture -x "$out/last.png" 2>/dev/null || true
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  pkill -f "^$app/Contents/MacOS/" || true
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
  cp "$data"/logs/*.log "$out/" 2>/dev/null || true
}
trap finish EXIT

# logged TEXT: the core's log says TEXT (the updater writes there too).
logged() { grep -qF -- "$1" "$data"/logs/*.log 2>/dev/null; }
# stopped: no program of the app runs.
stopped() { ! pgrep -f "^$app/Contents/MacOS/" >/dev/null; }
# wait_for WHAT SECONDS COMMAND...: until COMMAND succeeds.
wait_for() {
  local what="$1" left="$2"
  shift 2
  until "$@"; do
    left=$((left - 1))
    [ "$left" -gt 0 ] || { echo "timed out waiting for $what" >&2; return 1; }
    sleep 1
  done
  echo "$what: done"
}

# The two cores, for this Mac's processor, with the test key.
public="$(cd "$root/core" && go run ./tools/sign -keygen "$work/test.signing-key")"
arch="$(uname -m)"
[ "$arch" != x86_64 ] || arch=amd64
for v in "$version" "$next"; do
  (cd "$root/core" && CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" go build -trimpath \
    -ldflags "-s -w -X $module/internal/version.Current=$v -X $module/internal/signing.Key=$public" \
    -o "$work/core-$v" ./cmd/firefox-vpn-core)
done

# bundle DIR VERSION: the built app in DIR with that version's core, sealed
# again as the build seals it.
bundle() {
  mkdir -p "$1"
  tar -xzf "$root/dist/Firefox-VPN-$version-macOS.tar.gz" -C "$1"
  cp "$work/core-$2" "$1/Firefox VPN.app/Contents/MacOS/firefox-vpn-core"
  codesign --force --sign - "$1/Firefox VPN.app/Contents/MacOS/firefox-vpn-core"
  codesign --force --sign - "$1/Firefox VPN.app"
}
bundle "$work/old" "$version"
bundle "$work/new" "$next"
mv "$work/old/Firefox VPN.app" "$app"

# The test release, as the release job makes one; updates.json, which
# offers it to macOS; and GitHub's answer for the latest release, which the
# app asks only without updates.json.
release="$work/www/releases/download/v$next"
mkdir -p "$release"
COPYFILE_DISABLE=1 tar --no-mac-metadata -czf "$release/Firefox-VPN-$next-macOS.tar.gz" -C "$work/new" "Firefox VPN.app"
(cd "$release" && shasum -a 256 "Firefox-VPN-$next-macOS.tar.gz" >SHA256SUMS.txt)
(cd "$root/core" && go run ./tools/sign -key "$work/test.signing-key" "$release/SHA256SUMS.txt")
printf '{"macos": "%s"}\n' "$next" >"$work/www/updates.json"
printf '{"tag_name": "v%s", "html_url": "%s/releases/tag/v%s"}\n' "$next" "$server" "$next" >"$work/www/releases/latest"
python3 -m http.server 18080 --bind 127.0.0.1 --directory "$work/www" >"$out/server.log" 2>&1 &
server_pid=$!

echo "== $version finds $next and downloads it"
FIREFOX_VPN_UPDATE_SERVER="$server" "$app/Contents/MacOS/Firefox VPN" >>"$out/app.log" 2>&1 &
first=$!
wait_for "the download" 240 logged "update: version=$next downloaded"
grep -q "GET /updates.json" "$out/server.log" || { echo "the app did not read updates.json" >&2; exit 1; }
sleep 3
screencapture -x "$out/downloaded.png" || true
kill "$first"
wait_for "the app to quit" 60 stopped

# As at sign-in: launchd starts the app with --autostart, and ends the job's
# processes when the app quits for the update; the update must outlive it.
echo "== the next start, at sign-in, installs $next"
mkdir -p "$(dirname "$agent")"
cat >"$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>
		<string>$app/Contents/MacOS/Firefox VPN</string>
		<string>--autostart</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$agent"
wait_for "the new version's start" 240 logged "update: installed from=$version to=$next"
sleep 5
screencapture -x "$out/updated.png" || true

got="$("$app/Contents/MacOS/firefox-vpn-core" -version)"
[ "$got" = "$next" ] || { echo "the app's core is $got, not $next" >&2; exit 1; }
# Started again as it was: in the menu bar.
pgrep -fl "^$app/Contents/MacOS/Firefox VPN --autostart" || { echo "the new version does not run" >&2; exit 1; }
if logged "opening the app failed"; then
  echo "Launch Services did not open the new version; the core started it" >&2
  exit 1
fi
codesign --verify --deep --strict "$app"
echo "== updated from $version to $next"
