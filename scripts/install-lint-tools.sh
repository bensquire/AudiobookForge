#!/usr/bin/env bash
# Install the exact SwiftFormat + SwiftLint versions the lint gate is
# tuned for, into build/tools/bin (gitignored). scripts/lint.sh and
# scripts/format.sh put that directory first on PATH when it exists.
#
# Why not brew: the CI image preinstalls whatever versions it was built
# with (and `brew install` is a no-op on an installed formula), so the
# lint step silently drifts whenever the image refreshes — and a minor
# SwiftFormat bump routinely changes rule output enough to fail
# `--strict` with zero repo changes. Pinning here makes local and CI
# runs identical.
#
# Usage:
#   scripts/install-lint-tools.sh          # idempotent; skips if versions match
set -euo pipefail

SWIFTFORMAT_VERSION="0.63.0"
SWIFTLINT_VERSION="0.65.1"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/tools/bin"
mkdir -p "$BIN"

have_version() {
  # $1 = binary path, $2 = wanted version
  [[ -x "$1" ]] && [[ "$("$1" --version 2>/dev/null | tr -d '[:space:]')" == "$2" ]]
}

fetch_zip() {
  # $1 = url, $2 = member path inside the zip, $3 = destination
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL "$1" -o "$tmp/tool.zip"
  unzip -q -o "$tmp/tool.zip" -d "$tmp/x"
  cp -f "$tmp/x/$2" "$3"
  chmod +x "$3"
  rm -rf "$tmp"
}

if have_version "$BIN/swiftformat" "$SWIFTFORMAT_VERSION"; then
  echo "==> swiftformat $SWIFTFORMAT_VERSION already installed"
else
  echo "==> installing swiftformat $SWIFTFORMAT_VERSION"
  fetch_zip \
    "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip" \
    "swiftformat" "$BIN/swiftformat"
fi

if have_version "$BIN/swiftlint" "$SWIFTLINT_VERSION"; then
  echo "==> swiftlint $SWIFTLINT_VERSION already installed"
else
  echo "==> installing swiftlint $SWIFTLINT_VERSION"
  fetch_zip \
    "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip" \
    "swiftlint" "$BIN/swiftlint"
fi

echo
echo "swiftformat: $("$BIN/swiftformat" --version)"
echo "swiftlint:   $("$BIN/swiftlint" --version)"
