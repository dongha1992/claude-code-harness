#!/usr/bin/env bash
# 공통 config 로더 — 모든 훅 스크립트에서 source 해서 사용
# Usage: source "$(dirname "$0")/load-config.sh"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG_FILE="$REPO_ROOT/.claude/harness.config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[harness] harness.config.json not found at $CONFIG_FILE" >&2
  echo "[harness] Run: cp .claude/harness.config.example.json .claude/harness.config.json" >&2
  exit 0
fi

# config 값 읽기 헬퍼
cfg() {
  jq -r "$1 // empty" "$CONFIG_FILE" 2>/dev/null
}

# 자주 쓰이는 값 미리 로드
CFG_SRC_DIR=$(cfg '.srcDir')
CFG_TEST_DIR=$(cfg '.testDir')
CFG_TEST_RUNNER=$(cfg '.testRunner')
CFG_TEST_CLIENT_DIR=$(cfg '.testClientDir')
CFG_LINT_COMMAND=$(cfg '.lintCommand')
CFG_TSC_COMMAND=$(cfg '.tscCommand')
CFG_LINT_DETECT=$(cfg '.lintDetectPattern')
CFG_TSC_DETECT=$(cfg '.tscDetectPattern')
CFG_POLICY_PATTERNS=$(cfg '.policyPatterns')
CFG_PROGRESS_FILE=$(cfg '.progressFile')
CFG_SOURCE_EXTS=$(jq -r '.sourceExtensions // ["ts","tsx"] | join("|")' "$CONFIG_FILE" 2>/dev/null)

# trackDirs를 파이프로 연결된 grep 패턴으로
CFG_TRACK_DIRS=$(jq -r '.trackDirs // [] | map("^" + .) | join("|")' "$CONFIG_FILE" 2>/dev/null)

# protectedPaths 배열
CFG_PROTECTED_PATHS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && CFG_PROTECTED_PATHS+=("$p")
done < <(jq -r '.protectedPaths[]? // empty' "$CONFIG_FILE" 2>/dev/null)

# testFilePatterns 배열
CFG_TEST_PATTERNS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && CFG_TEST_PATTERNS+=("$p")
done < <(jq -r '.testFilePatterns[]? // empty' "$CONFIG_FILE" 2>/dev/null)

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
