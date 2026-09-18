#!/usr/bin/env bash
# 공통 config 로더 — 모든 훅 스크립트에서 source 해서 사용
# Usage: source "$(dirname "$0")/load-config.sh"
# 의존성: Node.js (jq 불필요)

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG_FILE="$REPO_ROOT/.claude/harness.config.json"
_HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[harness] harness.config.json not found at $CONFIG_FILE" >&2
  echo "[harness] Run: bash .claude/setup.sh" >&2
  exit 0
fi

# Node.js로 config 파싱 → shell 변수로 변환
eval "$(node "$_HOOKS_DIR/parse-config.js" "$CONFIG_FILE")"

# JSON 파싱 헬퍼 로드 (stdin에서 hook input 읽는 용도)
source "$_HOOKS_DIR/parse-json.sh"

# protectedPaths 배열 변환
CFG_PROTECTED_PATHS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && CFG_PROTECTED_PATHS+=("$p")
done <<< "$CFG_PROTECTED_PATHS_RAW"

# testFilePatterns 배열 변환
CFG_TEST_PATTERNS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && CFG_TEST_PATTERNS+=("$p")
done <<< "$CFG_TEST_PATTERNS_RAW"

# 테스트 파일 찾기 헬퍼
# Usage: find_test_file "/abs/path/to/file.ts"
# Sets: FOUND_TEST_FILE (empty if not found)
find_test_file() {
  local file_path="$1"
  local dir=$(dirname "$file_path")
  local basename=$(basename "$file_path")
  local name="${basename%.*}"
  FOUND_TEST_FILE=""

  for pattern in "${CFG_TEST_PATTERNS[@]}"; do
    local candidate="${pattern//\{dir\}/$dir}"
    candidate="${candidate//\{name\}/$name}"
    if [[ -f "$candidate" ]]; then
      FOUND_TEST_FILE="$candidate"
      return 0
    fi
  done
  return 1
}

# 소스 파일 확장자 매칭 헬퍼
is_source_file() {
  echo "$1" | grep -qE "\.(${CFG_SOURCE_EXTS})$"
}

# 테스트 파일 여부 확인
is_test_file() {
  [[ "$1" =~ \.(test|spec)\.(ts|tsx|js|jsx)$ ]] || [[ "$1" =~ /__tests__/ ]]
}

# trackDirs에 포함되는 파일인지
is_tracked_file() {
  [[ -n "$CFG_TRACK_DIRS" ]] && echo "$1" | grep -qE "$CFG_TRACK_DIRS"
}

# 오늘 세션에서 테스트 파일이 아닌 소스 파일이 변경됐는지 확인
# Usage: has_source_changes_today
# Return: 0 = 변경 있음, 1 = 변경 없음(세션 파일 없음/오늘 세션 아님 포함)
has_source_changes_today() {
  local session_file="$REPO_ROOT/.claude/hooks/state/session-files.txt"
  [[ -f "$session_file" ]] || return 1

  local today file_date
  today=$(date '+%Y-%m-%d')
  file_date=$(date -r "$session_file" '+%Y-%m-%d' 2>/dev/null || echo "")
  [[ "$file_date" == "$today" ]] || return 1

  local ts_changes
  ts_changes=$(grep -E "\.(${CFG_SOURCE_EXTS})$" "$session_file" 2>/dev/null \
    | grep -v '\.test\.\(ts\|tsx\)$' \
    | grep -v '__tests__' \
    | head -1 || true)
  [[ -n "$ts_changes" ]]
}

# 이번 세션에서 소스 파일이 수정됐는데 lint/tsc 게이트를 통과하지 않았는지 확인
# Usage: check_quality_gates
# Sets: GATE_MISSING (공백 구분 "lint"/"tsc" 조합, 문제 없으면 빈 문자열)
# Return: 0 = 소스 변경 없음 또는 게이트 통과, 1 = 게이트 미통과
check_quality_gates() {
  GATE_MISSING=""

  has_source_changes_today || return 0

  local lint_ok_file="$REPO_ROOT/.claude/hooks/state/lint-ok"
  local tsc_ok_file="$REPO_ROOT/.claude/hooks/state/tsc-ok"

  [[ -f "$lint_ok_file" ]] || GATE_MISSING="lint"
  [[ -f "$tsc_ok_file" ]]  || GATE_MISSING="$GATE_MISSING${GATE_MISSING:+ }tsc"

  [[ -z "$GATE_MISSING" ]] && return 0
  return 1
}
