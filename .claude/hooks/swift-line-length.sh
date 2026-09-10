#!/usr/bin/env bash
# PostToolUse hook: flag over-long lines in an edited Swift file.
#
# swiftformat.sh has just reflowed the file, but SwiftFormat only breaks what it
# can: a long string, a long doc comment or a long assertion message stays long,
# and those are exactly the lines an agent writes. So every line is measured
# against .swiftformat's `--maxwidth` after formatting, and the offenders are
# reported with their widths so the fix needs no second pass to find them.
#
# Advisory (exit 2) rather than blocking, like swiftlint.sh.
set -euo pipefail

# shellcheck source=.claude/hooks/hook-lib.sh
source "$(dirname "$0")/hook-lib.sh"

file="$(hook_file_path)"

case "$file" in
  *.swift) : ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# The limit is .swiftformat's `--maxwidth`, read from the config so the two can't
# drift; 110 is the fallback if the config is missing or the option absent.
config="${CLAUDE_PROJECT_DIR:-.}/.swiftformat"
limit=110
if [ -f "$config" ]; then
  parsed="$(awk '$1 == "--maxwidth" { print $2 }' "$config" 2>/dev/null | head -1 || true)"
  case "$parsed" in
    '' | *[!0-9]*) : ;;
    *) limit="$parsed" ;;
  esac
fi

# Counted in characters, not bytes: these sources carry em dashes and ellipses
# in their prose, and a byte count would flag a line three characters short of
# the limit.
findings="$(
  python3 -c '
import sys
limit = int(sys.argv[2])
for number, line in enumerate(open(sys.argv[1], encoding="utf-8", errors="replace"), 1):
    width = len(line.rstrip("\n"))
    if width > limit:
        print(f"  {number}: {width} columns")
' "$file" "$limit" 2>/dev/null || true
)"

if [ -n "$findings" ]; then
  {
    echo "Lines over $limit columns in $file:"
    printf '%s\n' "$findings"
    echo "  Reflow them — SwiftFormat could not break these on its own."
  } >&2
  exit 2
fi

exit 0
