#!/usr/bin/env bash
# Install dev dependencies (XcodeGen) and fetch the bundled ffmpeg binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing xcodegen via Homebrew"
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required. Install from https://brew.sh first." >&2
    exit 1
  fi
  brew install xcodegen
fi

bash "$ROOT/scripts/fetch-ffmpeg.sh"

echo "==> Generating Xcode project"
xcodegen generate

echo
echo "Bootstrap complete. Next:"
echo "  scripts/build.sh             # build a .app into ./build"
echo "  open AudiobookForge.xcodeproj  # open in Xcode"
