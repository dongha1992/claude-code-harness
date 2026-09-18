#!/usr/bin/env bash
# 다른 프로젝트에 이식됐을 때 깨지던 케이스에 대한 self-check.
# 임시 디렉터리에 .claude를 복사해서 돌리므로 실제 세션 상태를 건드리지 않는다.
# 실행: bash .claude/hooks/hooks-smoke.test.sh
set -uo pipefail

SRC_CLAUDE="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

cp -R "$SRC_CLAUDE" "$T/.claude"
rm -rf "$T/.claude/hooks/state" "$T/.claude/plans"
[[ -f "$T/.claude/harness.config.json" ]] || cp "$T/.claude/harness.config.example.json" "$T/.claude/harness.config.json"
mkdir -p "$T/src" "$T/.claude/hooks/state"
printf '{"type":"module"}\n' > "$T/package.json"
printf 'export const x = 1;\n' > "$T/src/foo.ts"

fail() { echo "❌ $1"; exit 1; }

expect_code() { # expect_code <기대코드> <설명> -- 이전 명령의 종료코드는 $?로 넘긴다
  [[ "$3" -eq "$1" ]] || fail "$2 (기대 exit $1, 실제 $3)"
}

# 1) "type": "module" 프로젝트에서도 위험 명령 훅이 살아있어야 한다 (fail-open 방지)
(cd "$T" && printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
  | bash .claude/hooks/pre-tool-use.sh >/dev/null 2>&1)
expect_code 2 "ESM 프로젝트에서 git push 승인 게이트가 동작해야 함" $?

# 2) 테스트 파일이 없는 소스 편집은 조용히 통과(exit 0)해야 한다
(cd "$T" && printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/foo.ts"}}' "$T" \
  | bash .claude/hooks/post-edit-test-runner.sh >/dev/null 2>&1)
expect_code 0 "테스트 파일 없는 편집은 exit 0이어야 함" $?

# 3) 소스 수정 후 lint/tsc 미실행이면 Stop을 막고, stop_hook_active면 다시 막지 않는다
echo "src/foo.ts" > "$T/.claude/hooks/state/session-files.txt"
(cd "$T" && printf '{"stop_hook_active":false}' | bash .claude/hooks/stop-done-guard.sh >/dev/null 2>&1)
expect_code 2 "게이트 미실행이면 Stop을 막아야 함" $?
(cd "$T" && printf '{"stop_hook_active":true}' | bash .claude/hooks/stop-done-guard.sh >/dev/null 2>&1)
expect_code 0 "stop_hook_active면 통과해야 함 (무한 루프 방지)" $?

# 4) cwd가 프로젝트 루트가 아니어도 CLAUDE_PROJECT_DIR로 상태 파일을 찾아야 한다
(cd "$T/.claude/hooks" && printf '{}' | CLAUDE_PROJECT_DIR="$T" bash "$T/.claude/hooks/stop-done-guard.sh" >/dev/null 2>&1)
expect_code 2 "비루트 cwd에서도 CLAUDE_PROJECT_DIR 기준으로 상태를 읽어야 함" $?

echo "✅ hooks-smoke: 4개 시나리오 모두 통과"
