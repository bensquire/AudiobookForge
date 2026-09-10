#!/usr/bin/env bash
# PostToolUse hook: format an edited Swift file with SwiftFormat against the
# repo's .swiftformat — the formatting authority. Running it on every edit keeps
# the tree formatted by construction, so formatting never shows up as a diff of
# its own.
#
# Reads the hook payload (JSON) on stdin; formats only *.swift files. Always
# exits 0 so a formatting hiccup never blocks the edit. Skipped if no swiftformat
# is available (run scripts/install-lint-tools.sh for the pinned one).
set -euo pipefail

# shellcheck source=.claude/hooks/hook-lib.sh
source "$(dirname "$0")/hook-lib.sh"

file="$(hook_file_path)"

case "$file" in
  *.swift) : ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

tool="$(hook_tool swiftformat)"
[ -n "$tool" ] || exit 0

config="${CLAUDE_PROJECT_DIR:-.}/.swiftformat"
if [ -f "$config" ]; then
  "$tool" --config "$config" "$file" >/dev/null 2>&1 || true
else
  "$tool" "$file" >/dev/null 2>&1 || true
fi

exit 0
