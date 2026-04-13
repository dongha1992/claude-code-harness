#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

CHECKPOINT_DIR="$REPO_ROOT/.checkpoint"
mkdir -p "$CHECKPOINT_DIR"

# 이번 세션에서 수정된 파일만 대상으로 한다
SESSION_FILE="$REPO_ROOT/.claude/hooks/state/session-files.txt"

if [[ ! -f "$SESSION_FILE" ]]; then
  exit 0
fi

# 오늘 세션 파일인지 확인
TODAY=$(date '+%Y-%m-%d')
FILE_DATE=$(date -r "$SESSION_FILE" '+%Y-%m-%d' 2>/dev/null || echo "")
if [[ "$FILE_DATE" != "$TODAY" ]]; then
  exit 0
fi

CHANGED_FILES=$(sort -u "$SESSION_FILE" | grep -v '^$' || true)

if [[ -z "$CHANGED_FILES" ]]; then
  exit 0
fi

TESTED_OK_FILE="$REPO_ROOT/.claude/hooks/state/tested-ok.txt"

echo "📁 변경된 파일 기반 체크포인트 생성 중..."

while IFS= read -r FILE_PATH; do
  [[ -z "$FILE_PATH" ]] && continue

  # 테스트 파일, trackDirs 외 경로 제외
  is_test_file "$FILE_PATH" && continue
  is_tracked_file "$FILE_PATH" || continue

  # 체크포인트 이름 결정
  FEATURE_NAME=$(basename "$FILE_PATH" | sed 's/\.[^.]*$//')
  case "$FEATURE_NAME" in
    route|index|layout|page|loading|error|not-found|middleware)
      FEATURE_NAME=$(echo "$FILE_PATH" | sed "s|.*${CFG_SRC_DIR}/||" | sed 's|/[^/]*$||' | tr '/' '-' | tr -d '[]')
      ;;
  esac

  CHECKPOINT_FILE="$CHECKPOINT_DIR/${FEATURE_NAME}.done"

  if [[ -f "$CHECKPOINT_FILE" ]]; then
    echo "ℹ️  이미 존재: $CHECKPOINT_FILE"
    continue
  fi

  # 테스트 파일 탐색
  find_test_file "$REPO_ROOT/$FILE_PATH"
  TEST_FILE="$FOUND_TEST_FILE"

  if [[ -z "$TEST_FILE" ]]; then
    echo "⚠️  테스트 파일 없음: $FILE_PATH → 체크포인트 생성 건너뜀"
    continue
  fi

  # PostToolUse에서 이미 통과한 파일은 재실행 없이 체크포인트 생성
  if grep -qxF "$FILE_PATH" "$TESTED_OK_FILE" 2>/dev/null; then
    touch "$CHECKPOINT_FILE"
    echo "✅ 체크포인트 생성 (캐시): $CHECKPOINT_FILE (← $FILE_PATH)"
    continue
  fi

  echo "🧪 테스트 실행: $TEST_FILE"
  RELATIVE_TEST="${TEST_FILE#$REPO_ROOT/$CFG_TEST_CLIENT_DIR/}"

  if (cd "$REPO_ROOT/$CFG_TEST_CLIENT_DIR" && $CFG_TEST_RUNNER "$RELATIVE_TEST" --reporter=verbose 2>&1); then
    touch "$CHECKPOINT_FILE"
    echo "✅ 체크포인트 생성: $CHECKPOINT_FILE (← $FILE_PATH)"
  else
    echo "❌ 테스트 실패 → 체크포인트 생성 안 함: $FILE_PATH"
  fi

done <<< "$CHANGED_FILES"

exit 0
