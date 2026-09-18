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

# 5) tscCommand=auto는 tsconfig 구조를 보고 결정한다 (references면 tsc -b, 아니면 --noEmit, 직접 지정 값이 우선)
tsc_cmd() { # tsc_cmd <tscCommand 설정값>
  node -e 'const c=require(process.argv[1]);c.tscCommand=process.argv[2];c.testClientDir=".";require("fs").writeFileSync(process.argv[3],JSON.stringify(c))' \
    "$T/.claude/harness.config.example.json" "$1" "$T/.claude/case.config.json"
  node "$T/.claude/hooks/parse-config.js" "$T/.claude/case.config.json" tscCommand
}
[[ "$(tsc_cmd auto)" == "npx tsc --noEmit" ]] || fail "tsconfig 없으면 npx tsc --noEmit이어야 함"
printf '{ "compilerOptions": {} }\n' > "$T/tsconfig.json"
[[ "$(tsc_cmd auto)" == "npx tsc --noEmit" ]] || fail "references 없는 tsconfig는 npx tsc --noEmit이어야 함"
printf '// solution style\n{ "files": [], "references": [ { "path": "./tsconfig.app.json" } ] }\n' > "$T/tsconfig.json"
[[ "$(tsc_cmd auto)" == "npx tsc -b" ]] || fail "references 구조면 npx tsc -b여야 함 (--noEmit은 아무것도 검사 안 함)"
[[ "$(tsc_cmd 'pnpm typecheck')" == "pnpm typecheck" ]] || fail "직접 지정한 tscCommand가 우선해야 함"

# 6) 게이트를 통과했어도 "## Status: done" 없는 계획이 있으면 Stop을 막는다 (scope-guard와 같은 규칙)
touch "$T/.claude/hooks/state/lint-ok" "$T/.claude/hooks/state/tsc-ok"
mkdir -p "$T/.claude/plans"
printf '# plan\n' > "$T/.claude/plans/a.md"
(cd "$T" && printf '{}' | bash .claude/hooks/stop-done-guard.sh >/dev/null 2>&1)
expect_code 2 "done 마커 없는 계획이 있으면 Stop을 막아야 함" $?
printf '\n## Status: done\n' >> "$T/.claude/plans/a.md"
(cd "$T" && printf '{}' | bash .claude/hooks/stop-done-guard.sh >/dev/null 2>&1)
expect_code 0 "모든 계획이 done이고 게이트 통과면 Stop을 허용해야 함" $?

# 7) 테스트 실패 시 tested-ok.txt에서 해당 파일을 지운다 (마지막 한 줄이어도 비정상 종료·잔여 .tmp 없이)
node -e 'const f=process.argv[1],c=JSON.parse(require("fs").readFileSync(f));c.testRunner="false";c.testRunnerArgs="";require("fs").writeFileSync(f,JSON.stringify(c))' "$T/.claude/harness.config.json"
printf 'it("x",()=>{});\n' > "$T/src/foo.test.ts"
printf 'src/foo.ts\n' > "$T/.claude/hooks/state/tested-ok.txt"
(cd "$T" && printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/foo.ts"}}' "$T" \
  | bash .claude/hooks/post-edit-test-runner.sh >/dev/null 2>&1)
expect_code 2 "테스트 실패면 exit 2여야 함" $?
grep -q "src/foo.ts" "$T/.claude/hooks/state/tested-ok.txt" && fail "실패한 파일이 tested-ok.txt에 남아있음"
[[ -e "$T/.claude/hooks/state/tested-ok.txt.tmp" ]] && fail "빈 .tmp 파일이 남아있음"

echo "✅ hooks-smoke: 7개 시나리오 모두 통과"
