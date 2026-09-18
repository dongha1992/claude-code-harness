#!/usr/bin/env bash
# =============================================================================
# Claude Code Harness 초기화 스크립트
# 새 프로젝트에서 실행: bash .claude/setup.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔧 Claude Code Harness 초기화"
echo "  프로젝트: $PROJECT_ROOT"
echo ""

# 1. harness.config.json 생성
CONFIG_FILE="$SCRIPT_DIR/harness.config.json"
EXAMPLE_FILE="$SCRIPT_DIR/harness.config.example.json"

if [[ -f "$CONFIG_FILE" ]]; then
  echo "✅ harness.config.json 이미 존재 — 건너뜀"
else
  if [[ -f "$EXAMPLE_FILE" ]]; then
    cp "$EXAMPLE_FILE" "$CONFIG_FILE"
    echo "📝 harness.config.json 생성됨 (example에서 복사)"
    echo "   → 프로젝트에 맞게 수정하세요: $CONFIG_FILE"
  else
    echo "❌ harness.config.example.json이 없습니다"
    exit 1
  fi
fi

# 2. 필요한 디렉토리 생성
mkdir -p "$SCRIPT_DIR/hooks/state"
mkdir -p "$SCRIPT_DIR/plans"
mkdir -p "$SCRIPT_DIR/logs"
echo "📁 디렉토리 생성: hooks/state, plans, logs"

# 3. 훅 스크립트 실행 권한
chmod +x "$SCRIPT_DIR"/hooks/*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/hooks/*.js 2>/dev/null || true
echo "🔑 훅 스크립트 실행 권한 설정"

# 4. .gitignore 추가 (state, logs는 추적하지 않음)
GITIGNORE="$SCRIPT_DIR/.gitignore"
if [[ ! -f "$GITIGNORE" ]]; then
  cat > "$GITIGNORE" <<'EOF'
hooks/state/
hooks/guardrails.log
logs/
plans/
settings.local.json
EOF
  echo "📝 .claude/.gitignore 생성"
else
  echo "✅ .claude/.gitignore 이미 존재 — 건너뜀"
fi

echo ""
echo "✅ 초기화 완료!"
echo ""
echo "다음 단계:"
echo "  1. .claude/harness.config.json을 프로젝트에 맞게 수정"
echo "  2. CLAUDE.md에 프로젝트 규칙 작성"
echo "  3. Claude Code 세션 시작"
echo ""
echo "주요 설정 항목:"
echo "  srcDir          — 소스 코드 루트 (예: src, client/src)"
echo "  testRunner      — 테스트 실행 명령 (예: npx vitest run)"
echo "  testClientDir   — 테스트 실행 시 cd할 디렉토리"
echo "  protectedPaths  — 수정 차단할 경로 목록"
echo "  trackDirs       — 변경 추적할 디렉토리 목록"
