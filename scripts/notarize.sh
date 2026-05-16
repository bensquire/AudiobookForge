#!/usr/bin/env bash
# Submit a `.app` (zipped) or `.dmg` to Apple's notary service, wait for
# the verdict, and staple the ticket. Reusable from CI and local runs.
#
# Required env (CI: GitHub Secrets; local: from your shell):
#   APPLE_API_KEY_ID        — App Store Connect API key ID (10-char)
#   APPLE_API_ISSUER_ID     — App Store Connect issuer UUID
#   APPLE_API_KEY_PATH      — path to the AuthKey_XXXXXX.p8 file
#
# Usage:
#   scripts/notarize.sh <path/to/AudiobookForge.app or .dmg>
set -euo pipefail

TARGET="${1:?usage: notarize.sh <app-or-dmg>}"

: "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID not set}"
: "${APPLE_API_ISSUER_ID:?APPLE_API_ISSUER_ID not set}"
: "${APPLE_API_KEY_PATH:?APPLE_API_KEY_PATH not set}"

ext="${TARGET##*.}"
case "$ext" in
  app)
    # notarytool wants a zip/dmg/pkg, not a bare .app.
    UPLOAD="$(mktemp -d)/$(basename "$TARGET").zip"
    /usr/bin/ditto -c -k --keepParent "$TARGET" "$UPLOAD"
    ;;
  dmg|pkg|zip)
    UPLOAD="$TARGET"
    ;;
  *)
    echo "error: $TARGET must be .app, .dmg, .pkg, or .zip" >&2
    exit 1
    ;;
esac

echo "==> Submitting $UPLOAD to Apple notary"
# Tee so we can recover the submission ID for the log fetch below if the
# verdict is Invalid.
SUBMIT_LOG=$(mktemp)
if ! xcrun notarytool submit "$UPLOAD" \
       --key      "$APPLE_API_KEY_PATH" \
       --key-id   "$APPLE_API_KEY_ID" \
       --issuer   "$APPLE_API_ISSUER_ID" \
       --wait \
       --timeout 30m 2>&1 | tee "$SUBMIT_LOG"; then
  SUBMISSION_ID=$(grep -m1 -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$SUBMIT_LOG" | head -1 || true)
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo
    echo "==> Notarization failed — fetching diagnostic log for $SUBMISSION_ID"
    xcrun notarytool log "$SUBMISSION_ID" \
      --key    "$APPLE_API_KEY_PATH" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" \
      || true
  fi
  rm -f "$SUBMIT_LOG"
  exit 1
fi
rm -f "$SUBMIT_LOG"

# Staple the ticket. For .app, the original (not the zip) gets stapled —
# the zip was just a transport.
echo "==> Stapling notarization ticket"
xcrun stapler staple "$TARGET"

echo "==> Verifying staple"
xcrun stapler validate "$TARGET"
spctl --assess --type "$(case $ext in app) echo execute;; *) echo open;; esac)" \
      --verbose=4 "$TARGET" || true
