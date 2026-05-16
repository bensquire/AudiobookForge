#!/usr/bin/env bash
# Build a polished DMG containing a notarized AudiobookForge.app and an
# Applications symlink. Requires `create-dmg` (brew install create-dmg).
#
# Usage:
#   scripts/make-dmg.sh <path/to/AudiobookForge.app> <output.dmg>
set -euo pipefail

APP_PATH="${1:?usage: make-dmg.sh <app> <output.dmg>}"
OUT_DMG="${2:?usage: make-dmg.sh <app> <output.dmg>}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app not found at $APP_PATH" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg not installed. Run: brew install create-dmg" >&2
  exit 1
fi

# create-dmg expects a staging dir containing only what should appear in
# the mounted volume.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/"

# Remove any stale DMG at the target.
rm -f "$OUT_DMG"

create-dmg \
  --volname "AudiobookForge" \
  --window-pos 200 120 \
  --window-size 600 380 \
  --icon-size 100 \
  --icon "$(basename "$APP_PATH")" 150 190 \
  --hide-extension "$(basename "$APP_PATH")" \
  --app-drop-link 450 190 \
  --no-internet-enable \
  "$OUT_DMG" \
  "$STAGE"

echo "==> DMG written to $OUT_DMG"
