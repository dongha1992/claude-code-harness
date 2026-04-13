#!/usr/bin/env bash
# Stop hook: 소스 파일 수정 후 lint + tsc 미실행이면 블락
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

STATE_DIR="$REPO_ROOT/.claude/hooks/state"
SESSION_FILE="$STATE_DIR/session-files.txt"
LINT_OK_FILE="$STATE_DIR/lint-ok"
TSC_OK_FILE="$STATE_DIR/tsc-ok"

# 세션 파일 없으면 통과
if [[ ! -f "$SESSION_FILE" ]]; then
  exit 0
fi

# 오늘 세션인지 확인
TODAY=$(date '+%Y-%m-%d')
FILE_DATE=$(date -r "$SESSION_FILE" '+%Y-%m-%d' 2>/dev/null || echo "")
if [[ "$FILE_DATE" != "$TODAY" ]]; then
  exit 0
fi

# 이번 세션에서 수정된 소스 파일 있는지 확인 (테스트 파일 제외)
TS_CHANGES=$(grep -E "\.(${CFG_SOURCE_EXTS})$" "$SESSION_FILE" 2>/dev/null \
  | grep -v '\.test\.\(ts\|tsx\)$' \
  | grep -v '__tests__' \
  | head -1 || true)

if [[ -z "$TS_CHANGES" ]]; then
  exit 0
fi

# 활성 계획(Status: in-progress) 존재 여부 확인
PLANS_DIR="$REPO_ROOT/.claude/plans"
ACTIVE_PLAN=""
if [[ -d "$PLANS_DIR" ]]; then
  for f in "$PLANS_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    if grep -q "Status: in-progress" "$f" 2>/dev/null; then
      ACTIVE_PLAN=$(basename "$f")
      break
    fi
  done
fi

if [[ -n "$ACTIVE_PLAN" ]]; then
  echo "[done-guard] 활성 계획이 완료되지 않았습니다: $ACTIVE_PLAN" >&2
  echo "" >&2
  echo "구현이 끝났으면 /done 을 실행하세요." >&2
  echo "  /done 은 품질 게이트 검증 + 계획 완료 마커(Status: done) 추가를 자동으로 처리합니다." >&2
  exit 2
fi

MISSING=""
[[ ! -f "$LINT_OK_FILE" ]] && MISSING="$MISSING lint"
[[ ! -f "$TSC_OK_FILE" ]]  && MISSING="$MISSING tsc"

if [[ -z "$MISSING" ]]; then
  exit 0
fi

echo "[done-guard] 미실행:$MISSING" >&2
echo "" >&2
echo "이번 세션에서 소스 파일을 수정했지만 게이트를 통과하지 않았습니다." >&2
echo "" >&2
[[ ! -f "$LINT_OK_FILE" ]] && echo "  ❌ ESLint  →  $CFG_LINT_COMMAND" >&2
[[ ! -f "$TSC_OK_FILE" ]]  && echo "  ❌ tsc     →  $CFG_TSC_COMMAND" >&2
echo "" >&2
echo "(/done 커맨드를 실행하면 전체 게이트를 자동으로 통과합니다)" >&2
exit 2
