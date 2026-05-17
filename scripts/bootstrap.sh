#!/usr/bin/env bash
# Install dev dependencies and build the bundled ffmpeg.
# First run takes ~7-10 min because it builds ffmpeg + fdk-aac from
# source; subsequent runs short-circuit if the binary is already there.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

need=()
for cmd in xcodegen nasm pkg-config; do
  command -v "$cmd" >/dev/null 2>&1 || need+=("$cmd")
done
if [[ ${#need[@]} -gt 0 ]]; then
  echo "==> Installing via Homebrew: ${need[*]}"
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required. Install from https://brew.sh first." >&2
    exit 1
  fi
  brew install "${need[@]}"
fi

bash "$ROOT/scripts/build-ffmpeg.sh"

echo "==> Generating Xcode project"
xcodegen generate

echo
echo "Bootstrap complete. Next:"
echo "  scripts/build.sh             # build a .app into ./build"
echo "  open AudiobookForge.xcodeproj  # open in Xcode"
