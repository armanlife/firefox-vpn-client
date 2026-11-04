#!/usr/bin/env bash
# Prints a release's notes for <tag>: README.md's download table and nothing
# else, linking to this release's own files (their versioned names,
# Arman-VPN-1.2.3-...).
#
#   bash scripts/release-notes.sh v1.1.1
set -euo pipefail

tag="${1:?usage: release-notes.sh <tag>}"
version="${tag#v}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "## Download"
echo
# The table alone, from <table> to </table>.
awk '/^<table>/ { p = 1 } p { print } /^<\/table>/ && p { exit }' "$root/README.md" |
  sed -e "s|releases/latest/download/Arman-VPN-|releases/download/$tag/Arman-VPN-$version-|g" \
      -e "s|releases/latest/download/arman-vpn-core-|releases/download/$tag/arman-vpn-core-$version-|g" \
      -e "s|releases/latest/download/|releases/download/$tag/|g"
