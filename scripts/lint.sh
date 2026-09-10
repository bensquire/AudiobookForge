#!/usr/bin/env bash
# Lint-only pass — verifies formatting and rules without mutating files.
# CI runs this; locally, run scripts/format.sh first if it complains.
set -euo pipefail

# shellcheck source=lint-common.sh
source "$(dirname "$0")/lint-common.sh"
cd "$ROOT"

echo "==> swiftformat $("$SWIFTFORMAT" --version) (lint mode)"
"$SWIFTFORMAT" "${TARGETS[@]}" --lint

echo
echo "==> swiftlint $("$SWIFTLINT" --version)"
"$SWIFTLINT" --strict --quiet "${TARGETS[@]}"

echo
echo "Lint clean."
