#!/usr/bin/env bash
# Download static ffmpeg + ffprobe binaries for both arm64 and x86_64, then lipo
# them into universal binaries inside AudiobookForge/Resources/bin/.
#
# Sources:
#   arm64  : https://www.osxexperts.net  (community static builds)
#   x86_64 : https://evermeet.cx/ffmpeg  (long-standing static build host)
#
# NOTE on licensing: these builds include GPL-licensed components (x264 etc).
# For Mac App Store submission we will need to swap these for an LGPL-only
# ffmpeg or replace the encode pipeline with AVFoundation. See README.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/AudiobookForge/Resources/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"

fetch_arm64() {
  local tool="$1"
  echo "==> fetching arm64 $tool"
  curl -fsSL "https://www.osxexperts.net/${tool}71arm.zip" -o "$TMP/${tool}-arm64.zip"
  unzip -q -o "$TMP/${tool}-arm64.zip" -d "$TMP/arm64"
  find "$TMP/arm64" -name "$tool" -type f -exec mv {} "$TMP/${tool}.arm64" \;
}

fetch_x86_64() {
  local tool="$1"
  echo "==> fetching x86_64 $tool"
  # evermeet returns the latest release zip from this endpoint
  curl -fsSL "https://evermeet.cx/ffmpeg/getrelease/${tool}/zip" -o "$TMP/${tool}-x86_64.zip"
  unzip -q -o "$TMP/${tool}-x86_64.zip" -d "$TMP/x86_64"
  find "$TMP/x86_64" -name "$tool" -type f -exec mv {} "$TMP/${tool}.x86_64" \;
}

for tool in ffmpeg ffprobe; do
  if [[ -x "$OUT/$tool" ]]; then
    echo "==> $tool already present at $OUT/$tool (delete to refetch)"
    continue
  fi

  fetch_arm64 "$tool"
  fetch_x86_64 "$tool"

  echo "==> lipo-ing universal $tool"
  lipo -create "$TMP/${tool}.arm64" "$TMP/${tool}.x86_64" -output "$OUT/$tool"
  chmod +x "$OUT/$tool"
  file "$OUT/$tool"
done

echo
echo "ffmpeg binaries installed under: $OUT"
