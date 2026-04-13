#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

PROGRESS_FILE="$REPO_ROOT/$CFG_PROGRESS_FILE"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# 절대 경로 → 프로젝트 상대 경로
RELATIVE_PATH="${FILE_PATH#$REPO_ROOT/}"

# progress.md 자체 수정 시 무한 반복 방지
if [[ "$FILE_PATH" == "$PROGRESS_FILE" ]]; then
  exit 0
fi

# trackDirs에 포함된 파일만 기록 (테스트 파일 제외)
if ! is_tracked_file "$RELATIVE_PATH"; then
  exit 0
fi

if is_test_file "$RELATIVE_PATH"; then
  exit 0
fi

# progress.md 없으면 생성
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

# 세션 파일 추적 (stop-checkpoint.sh용) — stdout 없이 조용히 기록
SESSION_FILE="$REPO_ROOT/.claude/hooks/state/session-files.txt"
mkdir -p "$REPO_ROOT/.claude/hooks/state"

# 오늘 날짜가 아닌 파일이면 초기화 (새 세션 시작)
TODAY=$(date '+%Y-%m-%d')
if [[ -f "$SESSION_FILE" ]]; then
  FILE_DATE=$(date -r "$SESSION_FILE" '+%Y-%m-%d' 2>/dev/null || echo "")
  if [[ "$FILE_DATE" != "$TODAY" ]]; then
    : > "$SESSION_FILE"
  fi
fi

echo "$RELATIVE_PATH" >> "$SESSION_FILE"

# 소스 파일 수정 시 lint-ok, tsc-ok 무효화 (done-guard용)
if is_source_file "$RELATIVE_PATH"; then
  rm -f "$REPO_ROOT/.claude/hooks/state/lint-ok"
  rm -f "$REPO_ROOT/.claude/hooks/state/tsc-ok"
fi

exit 0
