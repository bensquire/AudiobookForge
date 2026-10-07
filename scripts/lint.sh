#!/usr/bin/env bash
# Lint-only pass — verifies formatting and line length without mutating files.
# CI runs this; locally, run scripts/format.sh first if it complains.
set -euo pipefail

# shellcheck source=lint-common.sh
source "$(dirname "$0")/lint-common.sh"
cd "$ROOT"

echo "==> swiftformat $("$SWIFTFORMAT" --version) (lint mode)"
"$SWIFTFORMAT" "${TARGETS[@]}" --lint

# SwiftFormat wraps code at --maxwidth 110 but leaves a long string or comment
# it cannot break, so every line is also held to 130 columns, which leaves room
# for an error message or a line of test data. Counted in characters, not bytes,
# so an em dash counts once.
echo
echo "==> line length (130 columns)"
python3 - 130 "${TARGETS[@]}" <<'PY_LINES'
import pathlib, sys
limit, targets = int(sys.argv[1]), sys.argv[2:]
long_lines = [
    f"{path}:{number}: {len(line)} columns"
    for target in targets
    for path in sorted(pathlib.Path(target).rglob("*.swift"))
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
    if len(line) > limit
]
print("\n".join(long_lines) or "no line over the limit")
sys.exit(1 if long_lines else 0)
PY_LINES

echo
echo "Lint clean."
