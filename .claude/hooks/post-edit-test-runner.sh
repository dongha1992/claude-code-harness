#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

FILE_PATH=$(parse_json "tool_input.file_path")
TESTED_OK_FILE="$REPO_ROOT/.claude/hooks/state/tested-ok.txt"
RELATIVE_FILE="${FILE_PATH#$REPO_ROOT/}"

[[ -z "$FILE_PATH" ]] && exit 0

is_test_file "$FILE_PATH" && exit 0

find_test_file "$FILE_PATH" || true
TEST_FILE="$FOUND_TEST_FILE"

[[ -z "$TEST_FILE" ]] && exit 0

NAME_WITHOUT_EXT=$(basename "$FILE_PATH" | sed 's/\.[^.]*$//')
echo "🧪 [$NAME_WITHOUT_EXT] 관련 테스트 실행: $TEST_FILE" >&2

cd "$REPO_ROOT/$CFG_TEST_CLIENT_DIR"

RELATIVE_TEST="${TEST_FILE#$REPO_ROOT/$CFG_TEST_CLIENT_DIR/}"

RUNNER_CMD="$CFG_TEST_RUNNER $RELATIVE_TEST"
[[ -n "$CFG_TEST_RUNNER_ARGS" ]] && RUNNER_CMD="$RUNNER_CMD $CFG_TEST_RUNNER_ARGS"

if eval "$RUNNER_CMD" 2>&1; then
  echo "✅ 테스트 통과" >&2
  mkdir -p "$(dirname "$TESTED_OK_FILE")"
  grep -qxF "$RELATIVE_FILE" "$TESTED_OK_FILE" 2>/dev/null || echo "$RELATIVE_FILE" >> "$TESTED_OK_FILE"
else
  echo "❌ 테스트 실패 — 수정 필요" >&2
  if [[ -f "$TESTED_OK_FILE" ]]; then
    grep -vxF "$RELATIVE_FILE" "$TESTED_OK_FILE" > "$TESTED_OK_FILE.tmp" && mv "$TESTED_OK_FILE.tmp" "$TESTED_OK_FILE"
  fi
  exit 2
fi
