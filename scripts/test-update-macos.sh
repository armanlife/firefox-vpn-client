#!/usr/bin/env bash
# Tries the macOS app's own update end to end, on CI's Mac (GitHub
# Actions), as a user's copy goes through it, from a version before the
# rename to Arman VPN (1.0.9) on: the released app of version <old>
# (Firefox VPN.app) goes to /Applications and updates itself with its own
# code to <v>, the app that scripts/build-macos.sh built (its tar.gz in
# dist/), which then updates itself to <v+1>, both from a test release on
# loopback. Each time the app finds the release through updates.json a
# minute after it starts, its core downloads it in the background, the
# next start (by the app's LaunchAgent, as at sign-in) installs it, and the
# new version opens through Launch Services, in the menu bar. On the way
# the data folder takes the new name (at <v>'s first start) and so does the
# bundle (at the update to <v+1>). The cores trust a key made for the test,
# which signs the test release; the old one is built from <old>'s source.
# It uses the app's own data folder and LaunchAgent, so it runs on CI only.
# Screenshots and logs go to $1 (default dist/update-test).
set -euo pipefail

[ "${GITHUB_ACTIONS:-}" = true ] || {
  echo "this replaces the app and its data in your account: it runs on CI's Mac only" >&2
  exit 1
}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' "$root/app/pubspec.yaml")"
next="${version%.*}.$((${version##*.} + 1))"
module=github.com/armanlife/arman-vpn-client/core
# The last version under the old name, and its names.
old_version=1.0.8
old_module=github.com/armanlife/firefox-vpn-client/core
old_app="/Applications/Firefox VPN.app"
old_data="$HOME/Library/Application Support/Firefox VPN Client"
out="${1:-$root/dist/update-test}"
app="/Applications/Arman VPN.app"
data="$HOME/Library/Application Support/Arman VPN"
server="http://127.0.0.1:18080"
work="$(mktemp -d)"
mkdir -p "$out"
for p in "$app" "$old_app" "$data" "$old_data"; do
  [ ! -e "$p" ] || { echo "$p is there already" >&2; exit 1; }
done

# The app's LaunchAgent, as the app writes it for starting at sign-in
# (app/macos/Runner/MainFlutterWindow.swift).
label=com.arman.firefoxvpn
agent="$HOME/Library/LaunchAgents/$label.plist"

server_pid=""
finish() {
  screencapture -x "$out/last.png" 2>/dev/null || true
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  pkill -f "^$app/Contents/MacOS/" || true
  pkill -f "^$old_app/Contents/MacOS/" || true
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
  cp "$data"/logs/*.log "$old_data"/logs/*.log "$out/" 2>/dev/null || true
  git -C "$root" worktree remove --force "$work/src-old" 2>/dev/null || true
}
trap finish EXIT

# logged TEXT: the core's log says TEXT (the updater writes there too), in
# the data folder under either name.
logged() { cat "$data"/logs/*.log "$old_data"/logs/*.log 2>/dev/null | grep -qF -- "$1"; }
# stopped: no program of the app runs, under either name.
stopped() { ! pgrep -f "^$app/Contents/MacOS/" >/dev/null && ! pgrep -f "^$old_app/Contents/MacOS/" >/dev/null; }
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

# The cores for this Mac's processor, with the test key: the old one from
# its version's source, the two new ones from this tree.
public="$(cd "$root/core" && go run ./tools/sign -keygen "$work/test.signing-key")"
arch="$(uname -m)"
[ "$arch" != x86_64 ] || arch=amd64
git -C "$root" fetch --quiet --depth 1 origin tag "v$old_version"
git -C "$root" worktree add --quiet "$work/src-old" "v$old_version"
(cd "$work/src-old/core" && CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" go build -trimpath \
  -ldflags "-s -w -X $old_module/internal/version.Current=$old_version -X $old_module/internal/signing.Key=$public" \
  -o "$work/core-$old_version" ./cmd/firefox-vpn-core)
for v in "$version" "$next"; do
  (cd "$root/core" && CGO_ENABLED=0 GOOS=darwin GOARCH="$arch" go build -trimpath \
    -ldflags "-s -w -X $module/internal/version.Current=$v -X $module/internal/signing.Key=$public" \
    -o "$work/core-$v" ./cmd/arman-vpn-core)
done

# The old app as its release has it, with its core trusting the test key,
# sealed again as the build seals it.
mkdir -p "$work/old"
curl -fsSL --retry 3 -o "$work/old.tar.gz" \
  "https://github.com/armanlife/arman-vpn-client/releases/download/v$old_version/Firefox-VPN-$old_version-macOS.tar.gz"
tar -xzf "$work/old.tar.gz" -C "$work/old"
cp "$work/core-$old_version" "$work/old/Firefox VPN.app/Contents/MacOS/firefox-vpn-core"
codesign --force --sign - "$work/old/Firefox VPN.app/Contents/MacOS/firefox-vpn-core"
codesign --force --sign - "$work/old/Firefox VPN.app"
mv "$work/old/Firefox VPN.app" "$old_app"

# bundle DIR VERSION: the built app in DIR with that version's core, sealed
# again as the build seals it.
bundle() {
  mkdir -p "$1"
  tar -xzf "$root/dist/Arman-VPN-$version-macOS.tar.gz" -C "$1"
  cp "$work/core-$2" "$1/Arman VPN.app/Contents/MacOS/arman-vpn-core"
  codesign --force --sign - "$1/Arman VPN.app/Contents/MacOS/arman-vpn-core"
  codesign --force --sign - "$1/Arman VPN.app"
  codesign --verify --deep --strict "$1/Arman VPN.app"
}
bundle "$work/new" "$version"
bundle "$work/next" "$next"

# The test releases, as the release job makes them: <v> under the old name
# too (the old app's update looks for that), <v+1> under the new one; and
# GitHub's answer for the latest release, which the app asks only without
# updates.json.
# release VERSION FILE DIR: the release of VERSION with DIR's app as FILE.
release() {
  local dir="$work/www/releases/download/v$1"
  mkdir -p "$dir"
  COPYFILE_DISABLE=1 tar --no-mac-metadata -czf "$dir/$2" -C "$3" "Arman VPN.app"
  (cd "$dir" && shasum -a 256 "$2" >SHA256SUMS.txt)
  (cd "$root/core" && go run ./tools/sign -key "$work/test.signing-key" "$dir/SHA256SUMS.txt")
}
release "$version" "Firefox-VPN-$version-macOS.tar.gz" "$work/new"
release "$next" "Arman-VPN-$next-macOS.tar.gz" "$work/next"
# offer VERSION: updates.json offers it to macOS.
offer() {
  printf '{"macos": "%s"}\n' "$1" >"$work/www/updates.json"
  printf '{"tag_name": "v%s", "html_url": "%s/releases/tag/v%s"}\n' "$1" "$server" "$1" >"$work/www/releases/latest"
}
offer "$version"
python3 -m http.server 18080 --bind 127.0.0.1 --directory "$work/www" >"$out/server.log" 2>&1 &
server_pid=$!

# agent EXE: the LaunchAgent that starts EXE at sign-in, loaded: launchd
# starts the app with --autostart, and ends the job's processes when the
# app quits for the update; the update must outlive it.
agent() {
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
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
		<string>$1</string>
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
}

# hop FROM TO EXE: the app at EXE, of version FROM, finds TO and downloads
# it, quits, and the next start at sign-in installs it.
hop() {
  echo "== $1 finds $2 and downloads it"
  FIREFOX_VPN_UPDATE_SERVER="$server" ARMAN_VPN_UPDATE_SERVER="$server" "$3" >>"$out/app.log" 2>&1 &
  local first=$!
  wait_for "the download of $2" 240 logged "update: version=$2 downloaded"
  grep -q "GET /updates.json" "$out/server.log" || { echo "the app did not read updates.json" >&2; exit 1; }
  sleep 3
  screencapture -x "$out/downloaded-$2.png" || true
  kill "$first"
  wait_for "the app to quit" 60 stopped
  echo "== the next start, at sign-in, installs $2"
  agent "$3"
  wait_for "the start of $2" 240 logged "update: installed from=$1 to=$2"
  sleep 5
  screencapture -x "$out/updated-$2.png" || true
  if logged "opening the app failed"; then
    echo "Launch Services did not open $2; the core started it" >&2
    exit 1
  fi
}

# From the old name: the old app's update puts the new one in its bundle,
# which keeps its name; the new app moves the data folder.
hop "$old_version" "$version" "$old_app/Contents/MacOS/Firefox VPN"
wait_for "the new version's start" 60 pgrep -f "^$old_app/Contents/MacOS/Arman VPN --autostart"
wait_for "the data folder's new name" 60 test -d "$data"
[ ! -e "$old_data" ] || { echo "the old data folder is still there" >&2; exit 1; }
got="$("$old_app/Contents/MacOS/arman-vpn-core" -version)"
[ "$got" = "$version" ] || { echo "the app's core is $got, not $version" >&2; exit 1; }
codesign --verify --deep --strict "$old_app"

# Under the new name: the update renames the bundle.
pkill -f "^$old_app/Contents/MacOS/" || true
wait_for "the app to quit" 60 stopped
offer "$next"
hop "$version" "$next" "$old_app/Contents/MacOS/Arman VPN"
wait_for "the bundle's new name" 60 test -d "$app"
[ ! -e "$old_app" ] || { echo "$old_app is still there" >&2; exit 1; }
got="$("$app/Contents/MacOS/arman-vpn-core" -version)"
[ "$got" = "$next" ] || { echo "the app's core is $got, not $next" >&2; exit 1; }
# Started again as it was: in the menu bar.
wait_for "the newest version's start" 60 pgrep -fl "^$app/Contents/MacOS/Arman VPN --autostart"
codesign --verify --deep --strict "$app"
echo "== updated from $old_version through $version to $next"
