#!/usr/bin/env bash
# Build AudiobookForge.app for local testing.
#
# Usage:
#   scripts/build.sh             # Debug build into ./build/Build/Products/Debug
#   scripts/build.sh release     # Release build, unsigned (good for smoke-tests)
#   scripts/build.sh archive     # .xcarchive for distribution (signing required)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-debug}"
DERIVED="$ROOT/build"

# Regenerate the xcodeproj from project.yml — cheap and keeps the project
# definition canonical in git.
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Run scripts/bootstrap.sh first." >&2
  exit 1
fi
xcodegen generate --quiet

case "$MODE" in
  debug)
    xcodebuild \
      -project AudiobookForge.xcodeproj \
      -scheme AudiobookForge \
      -configuration Debug \
      -derivedDataPath "$DERIVED" \
      CODE_SIGN_IDENTITY="-" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO \
      build
    APP="$DERIVED/Build/Products/Debug/AudiobookForge.app"
    echo
    echo "Built: $APP"
    echo "Open with: open '$APP'"
    ;;
  release)
    xcodebuild \
      -project AudiobookForge.xcodeproj \
      -scheme AudiobookForge \
      -configuration Release \
      -derivedDataPath "$DERIVED" \
      CODE_SIGN_IDENTITY="-" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO \
      build
    APP="$DERIVED/Build/Products/Release/AudiobookForge.app"
    echo
    echo "Built: $APP"
    ;;
  archive)
    ARCHIVE_PATH="$DERIVED/AudiobookForge.xcarchive"
    xcodebuild \
      -project AudiobookForge.xcodeproj \
      -scheme AudiobookForge \
      -configuration Release \
      -derivedDataPath "$DERIVED" \
      -archivePath "$ARCHIVE_PATH" \
      archive
    echo
    echo "Archive: $ARCHIVE_PATH"
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: $0 [debug|release|archive]" >&2
    exit 1
    ;;
esac
