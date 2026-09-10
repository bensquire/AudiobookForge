#!/usr/bin/env bash
# Auto-fix anything SwiftFormat can reach, then SwiftLint's autocorrect.
set -euo pipefail

# shellcheck source=lint-common.sh
source "$(dirname "$0")/lint-common.sh"
cd "$ROOT"

echo "==> swiftformat $("$SWIFTFORMAT" --version) (write)"
"$SWIFTFORMAT" "${TARGETS[@]}"

echo
echo "==> swiftlint $("$SWIFTLINT" --version) --fix (autocorrect)"
"$SWIFTLINT" --fix --quiet "${TARGETS[@]}"

echo
echo "Done. Re-run scripts/lint.sh to verify everything is clean."
