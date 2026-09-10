#!/usr/bin/env bash
# PostToolUse hook: lint an edited Swift file with SwiftLint against the repo's
# .swiftlint.yml. swiftformat.sh has already formatted the file; this catches the
# smells SwiftFormat cannot — an empty-count comparison, a redundant nil
# coalescing, an orphaned doc comment — at edit time rather than in review.
#
# Reads the hook payload (JSON) on stdin; lints only *.swift files. Advisory:
# findings go back to Claude (exit 2) rather than blocking the edit. Skipped if
# no swiftlint is available.
set -euo pipefail

# shellcheck source=.claude/hooks/hook-lib.sh
source "$(dirname "$0")/hook-lib.sh"

file="$(hook_file_path)"

case "$file" in
  *.swift) : ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

tool="$(hook_tool swiftlint)"
[ -n "$tool" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}"

# --strict so a warning counts; --quiet drops the progress banner so only
# findings reach stderr.
findings="$("$tool" lint --strict --quiet -- "$file" 2>/dev/null || true)"

if [ -n "$findings" ]; then
  {
    echo "SwiftLint flagged $file:"
    printf '%s\n' "$findings" | sed 's/^/  /'
    echo "  (Fix these before handing over; the rules left on in .swiftlint.yml are the ones that matter here.)"
  } >&2
  exit 2
fi

exit 0
