#!/usr/bin/env bash
# PostToolUse(Bash): tsc 실행 감지 → state/tsc-ok 생성
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

if echo "$COMMAND" | grep -qE "$CFG_TSC_DETECT"; then
  STATE_DIR="$REPO_ROOT/.claude/hooks/state"
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/tsc-ok"
fi

exit 0
