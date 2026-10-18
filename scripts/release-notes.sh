#!/usr/bin/env bash
# Prints the top of a release's notes for <tag>: README.md's download table
# and the notes under it, linking to this release's own files, and the
# install commands. CI adds GitHub's list of changes below it.
#
#   bash scripts/release-notes.sh v1.1.1
set -euo pipefail

tag="${1:?usage: release-notes.sh <tag>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
raw="https://raw.githubusercontent.com/armanlife/firefox-vpn-client/main/install.sh"

echo "## Download"
echo
# From the table up to the README's install section.
awk '/^<table>/ { p = 1 } /^### / && p { exit } p' "$root/README.md" |
  sed "s|releases/latest/download/|releases/download/$tag/|g"
cat <<EOF
### Install from the terminal

The app on macOS, or on a Linux desktop (no sudo):

\`\`\`bash
curl -fsSL $raw | bash -s -- desktop
\`\`\`

The core as a service, for a Linux server:

\`\`\`bash
curl -fsSL $raw | sudo bash
\`\`\`

Every file's SHA-256 is in \`SHA256SUMS.txt\`.

EOF
