#!/usr/bin/env bash
# Shared helpers for this repo's Claude Code hooks. Sourced, never executed, and
# side-effect-free at source time — each hook still owns its own `set -euo
# pipefail` and its own exit policy.
#
# Adapted from the Prospect repo's hooks, themselves adapted from
# AssemblyAI/blurt (MIT).

# Echo the `tool_input.file_path` from the hook payload on stdin, or nothing when
# the payload has no file path (a non-file tool) or can't be parsed. The one
# definition of the payload contract: every hook reads the same field.
hook_file_path() {
  python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' \
    2>/dev/null || true
}

# The pinned tool binary from scripts/install-lint-tools.sh if it is there, else
# whatever is on PATH, else nothing. $1 = tool name (swiftformat | swiftlint).
hook_tool() {
  local pinned="${CLAUDE_PROJECT_DIR:-.}/build/tools/bin/$1"
  if [ -x "$pinned" ]; then
    echo "$pinned"
  elif command -v "$1" >/dev/null 2>&1; then
    command -v "$1"
  fi
}
