#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

FILE_PATH=$(parse_json "tool_input.file_path")
TOOL_NAME=$(parse_json "tool_name")

PROGRESS_FILE="$REPO_ROOT/$CFG_PROGRESS_FILE"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

RELATIVE_PATH="${FILE_PATH#$REPO_ROOT/}"

if [[ "$FILE_PATH" == "$PROGRESS_FILE" ]]; then
  exit 0
fi

if ! is_tracked_file "$RELATIVE_PATH"; then
  exit 0
fi

if is_test_file "$RELATIVE_PATH"; then
  exit 0
fi

if [[ ! -f "$PROGRESS_FILE" ]]; then
  cat > "$PROGRESS_FILE" <<EOF
# Progress

## 자동 기록

EOF
fi

{
  echo ""
  echo "- [$TIMESTAMP] tool=$TOOL_NAME | file=$RELATIVE_PATH"
} >> "$PROGRESS_FILE"

SESSION_FILE="$REPO_ROOT/.claude/hooks/state/session-files.txt"
mkdir -p "$REPO_ROOT/.claude/hooks/state"

TODAY=$(date '+%Y-%m-%d')
if [[ -f "$SESSION_FILE" ]]; then
  FILE_DATE=$(date -r "$SESSION_FILE" '+%Y-%m-%d' 2>/dev/null || echo "")
  if [[ "$FILE_DATE" != "$TODAY" ]]; then
    : > "$SESSION_FILE"
  fi
fi

echo "$RELATIVE_PATH" >> "$SESSION_FILE"

if is_source_file "$RELATIVE_PATH"; then
  rm -f "$REPO_ROOT/.claude/hooks/state/lint-ok"
  rm -f "$REPO_ROOT/.claude/hooks/state/tsc-ok"
fi

exit 0
