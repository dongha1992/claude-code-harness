#!/usr/bin/env bash
# Stop hook: 소스 파일 수정 후 lint + tsc 미실행이면 블락
set -euo pipefail

source "$(dirname "$0")/load-config.sh"

# 이번 세션에서 소스 파일 변경이 없으면 통과
has_source_changes_today || exit 0

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

check_quality_gates && exit 0

echo "[done-guard] 미실행: $GATE_MISSING" >&2
echo "" >&2
echo "이번 세션에서 소스 파일을 수정했지만 게이트를 통과하지 않았습니다." >&2
echo "" >&2
[[ "$GATE_MISSING" == *lint* ]] && echo "  ❌ ESLint  →  $CFG_LINT_COMMAND" >&2
[[ "$GATE_MISSING" == *tsc* ]]  && echo "  ❌ tsc     →  $CFG_TSC_COMMAND" >&2
echo "" >&2
echo "(/done 커맨드를 실행하면 전체 게이트를 자동으로 통과합니다)" >&2
exit 2
