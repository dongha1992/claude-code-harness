#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

COMMAND=$(parse_json "tool_input.command")

if echo "$COMMAND" | grep -qE "$CFG_LINT_DETECT_PATTERN"; then
  STATE_DIR="$REPO_ROOT/.claude/hooks/state"
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/lint-ok"
fi

exit 0
