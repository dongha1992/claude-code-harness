#!/usr/bin/env bash
# check_quality_gates()에 대한 self-check.
# 프레임워크 없이 assert 스타일로 상태 파일을 직접 조작해 검증한다.
# 실행: bash .claude/hooks/load-config.test.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
source "$(dirname "${BASH_SOURCE[0]}")/load-config.sh"

STATE_DIR="$REPO_ROOT/.claude/hooks/state"
SESSION_FILE="$STATE_DIR/session-files.txt"
LINT_OK_FILE="$STATE_DIR/lint-ok"
TSC_OK_FILE="$STATE_DIR/tsc-ok"

# 기존 상태 백업 (테스트가 실제 세션 상태를 건드리지 않도록)
BACKUP_DIR=$(mktemp -d)
for f in session-files.txt lint-ok tsc-ok; do
  [[ -f "$STATE_DIR/$f" ]] && cp "$STATE_DIR/$f" "$BACKUP_DIR/$f"
done

restore() {
  rm -f "$SESSION_FILE" "$LINT_OK_FILE" "$TSC_OK_FILE"
  for f in session-files.txt lint-ok tsc-ok; do
    [[ -f "$BACKUP_DIR/$f" ]] && cp "$BACKUP_DIR/$f" "$STATE_DIR/$f"
  done
  rm -rf "$BACKUP_DIR"
}
trap restore EXIT

fail() {
  echo "❌ $1"
  exit 1
}

mkdir -p "$STATE_DIR"

# 시나리오 1: session-files.txt 없음 → 통과(exit 0), GATE_MISSING 비어있음
rm -f "$SESSION_FILE" "$LINT_OK_FILE" "$TSC_OK_FILE"
check_quality_gates && ok1=0 || ok1=1
[[ "$ok1" -eq 0 ]] || fail "시나리오1: session 파일 없으면 통과해야 함"
[[ -z "$GATE_MISSING" ]] || fail "시나리오1: GATE_MISSING이 비어있어야 함"

# 시나리오 2: 소스 변경 있음, lint/tsc 둘 다 통과 → exit 0
echo "src/foo.ts" > "$SESSION_FILE"
touch "$LINT_OK_FILE" "$TSC_OK_FILE"
check_quality_gates && ok2=0 || ok2=1
[[ "$ok2" -eq 0 ]] || fail "시나리오2: lint/tsc 둘 다 있으면 통과해야 함"

# 시나리오 3: lint만 누락 → exit 1, GATE_MISSING=lint
rm -f "$LINT_OK_FILE"
touch "$TSC_OK_FILE"
check_quality_gates && ok3=0 || ok3=1
[[ "$ok3" -eq 1 ]] || fail "시나리오3: lint 없으면 실패해야 함"
[[ "$GATE_MISSING" == "lint" ]] || fail "시나리오3: GATE_MISSING이 'lint'여야 함 (실제: $GATE_MISSING)"

# 시나리오 4: tsc만 누락 → exit 1, GATE_MISSING=tsc
touch "$LINT_OK_FILE"
rm -f "$TSC_OK_FILE"
check_quality_gates && ok4=0 || ok4=1
[[ "$ok4" -eq 1 ]] || fail "시나리오4: tsc 없으면 실패해야 함"
[[ "$GATE_MISSING" == "tsc" ]] || fail "시나리오4: GATE_MISSING이 'tsc'여야 함 (실제: $GATE_MISSING)"

# 시나리오 5: 둘 다 누락 → exit 1, GATE_MISSING="lint tsc"
rm -f "$LINT_OK_FILE" "$TSC_OK_FILE"
check_quality_gates && ok5=0 || ok5=1
[[ "$ok5" -eq 1 ]] || fail "시나리오5: 둘 다 없으면 실패해야 함"
[[ "$GATE_MISSING" == "lint tsc" ]] || fail "시나리오5: GATE_MISSING이 'lint tsc'여야 함 (실제: $GATE_MISSING)"

# 시나리오 6: 소스 변경이 테스트 파일뿐 → 통과(exit 0)
rm -f "$LINT_OK_FILE" "$TSC_OK_FILE"
echo "src/foo.test.ts" > "$SESSION_FILE"
check_quality_gates && ok6=0 || ok6=1
[[ "$ok6" -eq 0 ]] || fail "시나리오6: 테스트 파일만 변경됐으면 통과해야 함"

echo "✅ check_quality_gates() 6개 시나리오 모두 통과"
