#!/usr/bin/env bash
# Lint-only pass — verifies formatting and rules without mutating files.
# CI runs this; locally, run scripts/format.sh first if it complains.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

missing=()
command -v swiftformat >/dev/null || missing+=("swiftformat")
command -v swiftlint   >/dev/null || missing+=("swiftlint")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing tools: ${missing[*]}" >&2
  echo "Install via: brew install swiftformat swiftlint" >&2
  exit 1
fi

echo "==> swiftformat (lint mode)"
# Newer SwiftFormat treats `--lint` as a flag-only; paths come first.
swiftformat AudiobookForge AudiobookForgeTests --lint

echo
echo "==> swiftlint"
swiftlint --strict --quiet AudiobookForge AudiobookForgeTests

echo
echo "Lint clean."
