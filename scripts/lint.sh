#!/usr/bin/env bash
# Lint-only pass — verifies formatting and rules without mutating files.
# CI runs this; locally, run scripts/format.sh first if it complains.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Prefer the pinned tool binaries from scripts/install-lint-tools.sh
# (what CI runs) over whatever brew happens to have installed.
if [[ -d "$ROOT/build/tools/bin" ]]; then
  export PATH="$ROOT/build/tools/bin:$PATH"
fi

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
swiftformat AudiobookForge AudiobookForgeTests ForgeCore ForgeCLI --lint

echo
echo "==> swiftlint"
swiftlint --strict --quiet AudiobookForge AudiobookForgeTests ForgeCore ForgeCLI

echo
echo "Lint clean."
