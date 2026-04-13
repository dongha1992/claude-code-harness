#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
TESTED_OK_FILE="$REPO_ROOT/.claude/hooks/state/tested-ok.txt"
RELATIVE_FILE="${FILE_PATH#$REPO_ROOT/}"

[[ -z "$FILE_PATH" ]] && exit 0

# 테스트 파일 자체 수정 시 무시
is_test_file "$FILE_PATH" && exit 0

# 매칭되는 테스트 파일 탐색
find_test_file "$FILE_PATH"
TEST_FILE="$FOUND_TEST_FILE"

# 매칭되는 테스트 파일 없으면 조용히 종료
[[ -z "$TEST_FILE" ]] && exit 0

NAME_WITHOUT_EXT=$(basename "$FILE_PATH" | sed 's/\.[^.]*$//')
echo "🧪 [$NAME_WITHOUT_EXT] 관련 테스트 실행: $TEST_FILE" >&2

# testClientDir 기준으로 실행
cd "$REPO_ROOT/$CFG_TEST_CLIENT_DIR"

# testClientDir 이후 상대 경로만 추출
RELATIVE_TEST="${TEST_FILE#$REPO_ROOT/$CFG_TEST_CLIENT_DIR/}"

if $CFG_TEST_RUNNER "$RELATIVE_TEST" --reporter=verbose 2>&1; then
  echo "✅ 테스트 통과" >&2
  # 통과 결과 캐싱 (stop-checkpoint.sh에서 재실행 방지)
  mkdir -p "$(dirname "$TESTED_OK_FILE")"
  grep -qxF "$RELATIVE_FILE" "$TESTED_OK_FILE" 2>/dev/null || echo "$RELATIVE_FILE" >> "$TESTED_OK_FILE"
else
  echo "❌ 테스트 실패 — 수정 필요" >&2
  # 실패 시 캐시에서 제거
  if [[ -f "$TESTED_OK_FILE" ]]; then
    grep -vxF "$RELATIVE_FILE" "$TESTED_OK_FILE" > "$TESTED_OK_FILE.tmp" && mv "$TESTED_OK_FILE.tmp" "$TESTED_OK_FILE"
  fi
  exit 2
fi
