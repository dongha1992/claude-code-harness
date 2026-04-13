#!/usr/bin/env bash
# PostToolUse(Bash): lint 실행 감지 → state/lint-ok 생성
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# lint 명령인지 확인
if echo "$COMMAND" | grep -qE "$CFG_LINT_DETECT"; then
  STATE_DIR="$REPO_ROOT/.claude/hooks/state"
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/lint-ok"
fi

exit 0
