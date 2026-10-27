#!/bin/bash
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/frazz1234/pip-island/main/scripts/get-pip.sh | bash
# Downloads the latest Pip.dmg, copies Pip into Applications and opens it.
set -euo pipefail

URL="https://github.com/frazz1234/pip-island/releases/latest/download/Pip.dmg"
TMP="$(mktemp -d)"
cleanup() { hdiutil detach "$TMP/mnt" -quiet -force 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

echo "Downloading Pip…"
curl -fsSL "$URL" -o "$TMP/Pip.dmg"
hdiutil attach "$TMP/Pip.dmg" -nobrowse -readonly -noautoopen -mountpoint "$TMP/mnt" -quiet

DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
pkill -x Pip 2>/dev/null || true
rm -rf "$DEST/Pip.app"
ditto "$TMP/mnt/Pip.app" "$DEST/Pip.app"
xattr -dr com.apple.quarantine "$DEST/Pip.app" 2>/dev/null || true

open "$DEST/Pip.app"
echo "Pip is installed in $DEST. Tap the island at the top of your screen to connect it to Claude Code."
