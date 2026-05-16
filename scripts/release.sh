#!/usr/bin/env bash
# Cut a local signed release: build → sign → notarize → DMG → notarize DMG.
# Mirrors the CI workflow so you can dry-run a release without pushing a tag.
#
# Prereqs:
#   - Developer ID Application cert installed in your login keychain
#   - $APPLE_TEAM_ID, $APPLE_API_KEY_ID, $APPLE_API_ISSUER_ID,
#     $APPLE_API_KEY_PATH set in your shell (see RELEASING.md)
#   - brew install xcodegen create-dmg
#
# Usage:
#   scripts/release.sh 0.1.0
set -euo pipefail

VERSION="${1:?usage: release.sh <version, e.g. 0.1.0>}"
BUILD="${BUILD:-$(git rev-list --count HEAD)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID not set}"

OUT_DIR="$ROOT/dist"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/AudiobookForge.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG="$OUT_DIR/AudiobookForge-$VERSION.dmg"

mkdir -p "$OUT_DIR"
rm -rf "$ARCHIVE" "$EXPORT_DIR"

# ---- ExportOptions rendered with the real team ID
EXPORT_OPTS="$BUILD_DIR/ExportOptions.rendered.plist"
mkdir -p "$BUILD_DIR"
TEAM_ID="$APPLE_TEAM_ID" envsubst < scripts/ExportOptions.plist > "$EXPORT_OPTS"

# ---- Ensure ffmpeg binaries are present
bash scripts/fetch-ffmpeg.sh

# ---- Regenerate Xcode project so project.yml stays the source of truth
xcodegen generate --quiet

echo "==> Archiving (version=$VERSION build=$BUILD team=$APPLE_TEAM_ID)"
xcodebuild \
  -project AudiobookForge.xcodeproj \
  -scheme AudiobookForge \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=Developer ID Application" \
  archive

echo "==> Exporting signed .app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath "$EXPORT_DIR"

APP_PATH="$EXPORT_DIR/AudiobookForge.app"

echo "==> Notarizing app"
bash scripts/notarize.sh "$APP_PATH"

echo "==> Building DMG"
bash scripts/make-dmg.sh "$APP_PATH" "$DMG"

echo "==> Signing DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "==> Notarizing DMG (so first-launch from the DMG is silent)"
bash scripts/notarize.sh "$DMG"

echo
echo "Done. Release artifact: $DMG"
