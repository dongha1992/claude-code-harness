#!/bin/bash
# Stop 훅: 이번 세션에서 수정된 파일에서 정책 키워드 탐지 + 테스트 존재 여부 확인
# exit 0: 정책 키워드 없음 (Gate 5: N/A)
# exit 1: 정책 키워드 있고 테스트 없는 파일 존재 → 테스트 작성 필요

source "$(dirname "$0")/load-config.sh"

SESSION_FILE="$REPO_ROOT/.claude/hooks/state/session-files.txt"

# 세션 파일 없으면 종료
if [[ ! -f "$SESSION_FILE" ]]; then
  exit 0
fi

# 오늘 세션 파일인지 확인
TODAY=$(date '+%Y-%m-%d')
FILE_DATE=$(date -r "$SESSION_FILE" '+%Y-%m-%d' 2>/dev/null || echo "")
if [[ "$FILE_DATE" != "$TODAY" ]]; then
  exit 0
fi

cd "$REPO_ROOT"

# 소스 파일만, 테스트 파일 제외
CHANGED=$(sort -u "$SESSION_FILE" \
  | grep -E "^${CFG_SRC_DIR}/" \
  | grep -Ev '\.(test|spec)\.(ts|tsx)$' \
  | grep -E "\.(${CFG_SOURCE_EXTS})$" || true)

if [[ -z "$CHANGED" ]]; then
  exit 0
fi

PATTERN="$CFG_POLICY_PATTERNS"

if [[ -z "$PATTERN" ]]; then
  exit 0
fi

HITS=$(echo "$CHANGED" | xargs grep -lE "$PATTERN" 2>/dev/null || true)

if [[ -z "$HITS" ]]; then
  exit 0
fi

echo "⚠️  정책 키워드 감지:"
MISSING=0

while IFS= read -r file; do
  [ -f "$file" ] || continue
  echo ""
  echo "  파일: $file"
  grep -nE "$PATTERN" "$file" | head -3 | sed 's/^/    /'

  find_test_file "$file"
  if [ -n "$FOUND_TEST_FILE" ]; then
    echo "    → ✅ 테스트: $FOUND_TEST_FILE"
  else
    echo "    → ❌ 테스트 없음"
    MISSING=1
  fi
done <<< "$HITS"

echo ""
if [ $MISSING -eq 1 ]; then
  echo "Gate 5: FAIL — 테스트 없는 정책 로직 존재. 테스트 작성 후 재실행."
else
  echo "Gate 5: PASS — 정책 키워드 있으나 테스트 존재."
fi

[ $MISSING -eq 1 ] && exit 2
exit 0
