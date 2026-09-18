#!/usr/bin/env bash
# =============================================================================
# Pre-Tool-Use 훅: 위험한 도구 사용을 실행 전에 차단
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/load-config.sh"

LOG_FILE=".claude/hooks/guardrails.log"

TOOL_NAME=$(parse_json "tool_name")

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_event() {
  local level="$1"
  local message="$2"
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "[$(timestamp)] $level | tool=$TOOL_NAME | message=$message | input=$(parse_json_raw)" >> "$LOG_FILE"
}

block() {
  local reason="$1"
  local msg
  msg="$(printf '🚫 [Guardrail 차단] %s\n\n이 작업은 프로젝트 Guardrails 정책에 의해 차단되었습니다.\n대안을 검토하거나, 필요한 경우 사람 관리자에게 승인을 요청하세요.' "$reason")"
  echo "$msg"
  echo "$msg" >&2
  log_event "BLOCKED" "$reason"
  exit 2
}

require_approval() {
  local reason="$1"
  local msg
  msg="$(printf '⚠️ [승인 필요] %s\n\n이 작업은 위험도가 있어 실행 전에 사용자 확인이 필요합니다.\n계속 진행할지 사용자의 명시적 승인을 받아주세요.' "$reason")"
  echo "$msg"
  echo "$msg" >&2
  log_event "APPROVAL_REQUIRED" "$reason"
  exit 2
}

# ── Bash 명령어 차단 ──
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(parse_json "tool_input.command")

  # 규칙 1: rm + 보호 경로 조합 차단
  if echo "$COMMAND" | grep -qE "^rm\s|[;&|]\s*rm\s"; then
    for path in "${CFG_PROTECTED_PATHS[@]}"; do
      if echo "$COMMAND" | grep -qF "$path"; then
        block "보호 경로($path)에 대한 rm 명령어 감지: $COMMAND"
      fi
    done
  fi

  # 규칙 2: .env 파일 직접 쓰기 차단
  if echo "$COMMAND" | grep -qE "(echo|printf|tee|cat\s*>)\s.*\.env\b"; then
    block ".env 파일 직접 쓰기 시도: $COMMAND"
  fi

  # 규칙 3: 프로덕션 DB 위험 명령어 차단
  if echo "$COMMAND" | grep -qiE "(psql|mysql|mongo)\s.*production|DROP\s+TABLE|TRUNCATE\s+TABLE"; then
    block "프로덕션 데이터베이스 위험 명령어: $COMMAND"
  fi

  # 규칙 4: git push 승인 필요
  if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git\s+push([[:space:]]|$)'; then
    require_approval "git push 실행 시도: $COMMAND"
  fi

  # 규칙 5: 패키지 배포 승인 필요
  if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])(npm|pnpm|yarn)\s+publish([[:space:]]|$)'; then
    require_approval "패키지 배포 명령 실행 시도: $COMMAND"
  fi

  # 규칙 6: docker push / gh release / vercel --prod 승인 필요
  if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])docker\s+push([[:space:]]|$)|(^|[;&|[:space:]])gh\s+release\s+create([[:space:]]|$)|vercel\s+--prod'; then
    require_approval "배포/릴리스 관련 명령 실행 시도: $COMMAND"
  fi

  # 규칙 7: git commit 전 lint + tsc 게이트 확인
  if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git\s+commit([[:space:]]|$)'; then
    if ! check_quality_gates; then
      msg="[commit-guard] git commit 차단: 게이트 미실행($GATE_MISSING)\n\n소스 파일을 수정했지만 게이트를 통과하지 않았습니다."
      [[ "$GATE_MISSING" == *lint* ]] && msg="$msg\n  ❌ ESLint  →  $CFG_LINT_COMMAND"
      [[ "$GATE_MISSING" == *tsc* ]]  && msg="$msg\n  ❌ tsc     →  $CFG_TSC_COMMAND"
      echo -e "$msg"
      echo -e "$msg" >&2
      exit 2
    fi
  fi
fi

# ── Write / Edit 보호 파일 차단 ──
if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" ]]; then
  FILE_PATH=$(parse_json "tool_input.file_path")

  for protected in "${CFG_PROTECTED_PATHS[@]}"; do
    if echo "$FILE_PATH" | grep -qF "$protected"; then
      block "보호 파일($protected) 직접 수정 시도"
    fi
  done
fi

exit 0
