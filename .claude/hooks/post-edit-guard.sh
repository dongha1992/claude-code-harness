#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)

STATE_DIR=".claude/hooks/state"
LOG_FILE="$STATE_DIR/edit-history.log"
mkdir -p "$STATE_DIR"

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# 수정 기록 저장
echo "$FILE_PATH" >> "$LOG_FILE"

# 최근 5번이 모두 같은 파일인지 확인
RECENT_FIVE=$(tail -n 5 "$LOG_FILE" 2>/dev/null || true)

if [[ -n "$RECENT_FIVE" ]]; then
    UNIQUE_COUNT=$(echo "$RECENT_FIVE" | sed '/^$/d' | sort | uniq | wc -l | tr -d ' ')
    LINE_COUNT=$(echo "$RECENT_FIVE" | sed '/^$/d' | wc -l | tr -d ' ')

    if [[ "$LINE_COUNT" -eq 5 && "$UNIQUE_COUNT" -eq 1 ]]; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        GUARDRAILS_LOG="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/hooks/guardrails.log"
        echo "[$TIMESTAMP] BLOCKED | tool=Edit | message=Doom Loop 감지 — 같은 파일 5회 연속 수정: $FILE_PATH" >> "$GUARDRAILS_LOG"

        echo "⚠️ [Doom Loop 감지]" >&2
        echo "같은 파일을 5번 연속 수정했습니다: $FILE_PATH" >&2
        echo "" >&2
        echo "접근 방식을 바꿔보세요." >&2
        echo "- 현재 실패 원인을 먼저 정리하기" >&2
        echo "- 테스트/로그를 먼저 확인하기" >&2
        echo "- 작은 단위로 수정하기" >&2
        echo "- 다른 파일이나 호출 흐름을 함께 점검하기" >&2
        exit 2
    fi
fi

exit 0
