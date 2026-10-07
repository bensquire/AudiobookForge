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

# SwiftFormat has no rule against `try!`, force unwraps or implicitly unwrapped
# optionals, so swift-format (in Xcode's toolchain) checks those three. Its own
# layout findings follow a different style from this repo's and are filtered out;
# files that import XCTest are exempt from the first two.
echo
echo "==> safety rules (swift-format: no try!, force unwrap or implicitly unwrapped optional)"
safety="$(
  swift format lint --configuration scripts/safety-rules.swift-format --recursive "${TARGETS[@]}" 2>&1 \
    | grep -E '\[(NeverUseForceTry|NeverForceUnwrap|NeverUseImplicitlyUnwrappedOptionals)\]' || true
)"
if [[ -n "$safety" ]]; then
  printf '%s\n' "$safety"
  exit 1
fi
echo "none"

echo
echo "Lint clean."
