#!/usr/bin/env bash
# Auto-fix anything SwiftFormat can reach. SwiftLint is checked but not
# auto-fixed (some of its fixes are opinionated and not all reviewable).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Prefer the pinned tool binaries from scripts/install-lint-tools.sh
# (what CI runs) over whatever brew happens to have installed.
if [[ -d "$ROOT/build/tools/bin" ]]; then
  export PATH="$ROOT/build/tools/bin:$PATH"
fi

if ! command -v swiftformat >/dev/null; then
  echo "swiftformat not found. Install with: brew install swiftformat" >&2
  exit 1
fi

echo "==> swiftformat (write)"
swiftformat AudiobookForge AudiobookForgeTests ForgeCore ForgeCLI

if command -v swiftlint >/dev/null; then
  echo
  echo "==> swiftlint --fix (autocorrect)"
  swiftlint --fix --quiet AudiobookForge AudiobookForgeTests ForgeCore ForgeCLI
fi

echo
echo "Done. Re-run scripts/lint.sh to verify everything is clean."
