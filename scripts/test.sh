#!/usr/bin/env bash
# Run the unit-test suite. Mirrors what CI runs so a local pass is
# load-bearing.
#
# Usage:
#   scripts/test.sh                 # whole suite
#   scripts/test.sh -only OutputPathResolverTests  # one class
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Run scripts/bootstrap.sh first." >&2
  exit 1
fi
xcodegen generate --quiet

ARGS=()
if [[ "${1:-}" == "-only" && -n "${2:-}" ]]; then
  ARGS+=(-only-testing:"AudiobookForgeTests/$2")
fi
# macOS ships bash 3.2, where "${ARGS[@]}" under `set -u` errors on an
# empty array. `${ARGS[@]+"${ARGS[@]}"}` below is the portable spelling
# of "all of ARGS, or nothing".
xcodebuild \
  -project AudiobookForge.xcodeproj \
  -scheme AudiobookForge \
  -configuration Debug \
  -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ${ARGS[@]+"${ARGS[@]}"} \
  test \
  | xcpretty 2>/dev/null || xcodebuild \
      -project AudiobookForge.xcodeproj \
      -scheme AudiobookForge \
      -configuration Debug \
      -derivedDataPath build \
      -destination 'platform=macOS' \
      CODE_SIGN_IDENTITY="-" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO \
      ${ARGS[@]+"${ARGS[@]}"} \
      test
