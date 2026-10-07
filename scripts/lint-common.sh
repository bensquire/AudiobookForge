#!/usr/bin/env bash
# Shared by lint.sh and format.sh: the Swift targets to check and the
# pinned tool binaries (installed on demand by install-lint-tools.sh so
# local runs and CI use identical versions — brew's SwiftFormat drifts,
# and a minor bump changes rule output).
#
# Source it; don't run it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS=(AudiobookForge AudiobookForgeTests ForgeCore ForgeCLI)

"$ROOT/scripts/install-lint-tools.sh" >/dev/null
SWIFTFORMAT="$ROOT/build/tools/bin/swiftformat"
