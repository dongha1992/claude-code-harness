# Claude Code Harness

Claude Code의 품질 게이트, 안전 장치, 워크플로우 자동화를 위한 하네스 세팅.

## 무엇을 하는가

| 훅 | 타이밍 | 역할 |
|---|---|---|
| `pre-tool-use.sh` | Edit/Write/Bash 전 | 위험 명령 차단, 보호 파일 수정 차단, commit 전 lint/tsc 게이트 |
| `scope-guard.js` | Edit/Write 전 | 계획 파일에 없는 파일 수정 차단 (스코프 크리프 방지) |
| `post-edit-test-runner.sh` | Edit/Write 후 | 수정된 파일의 관련 테스트 자동 실행 |
| `post-edit-guard.sh` | Edit/Write 후 | 같은 파일 5회 연속 수정 시 Doom Loop 감지 |
| `post-edit-progress.sh` | Edit/Write 후 | 변경 파일 추적, lint/tsc 상태 무효화 |
| `lint-tracker.sh` | Bash 후 | lint 실행 감지 → 게이트 통과 기록 |
| `tsc-tracker.sh` | Bash 후 | tsc 실행 감지 → 게이트 통과 기록 |
| `stop-done-guard.sh` | Stop 시 | 소스 수정 후 lint/tsc 미실행이면 차단 |

## 빠른 시작

### 방법 1: 이 템플릿에서 레포 생성

1. GitHub에서 **Use this template** 클릭
2. 새 프로젝트에서 초기화:

```bash
bash .claude/setup.sh
```

3. `.claude/harness.config.json`을 프로젝트에 맞게 수정

### 방법 2: 기존 프로젝트에 추가

```bash
npx degit your-username/claude-code-harness/.claude .claude
bash .claude/setup.sh
```

### 방법 3: 수동 복사

```bash
git clone https://github.com/your-username/claude-code-harness.git /tmp/harness
cp -r /tmp/harness/.claude your-project/.claude
cd your-project && bash .claude/setup.sh
```

## 설정

`bash .claude/setup.sh` 실행 후 `.claude/harness.config.json`을 프로젝트에 맞게 수정합니다.

주요 설정 항목:

| 키 | 설명 | 기본값 |
|---|---|---|
| `srcDir` | 소스 코드 루트 | `src` |
| `testRunner` | 테스트 실행 명령 | `npx vitest run` |
| `testClientDir` | 테스트 실행 시 cd할 디렉토리 | `.` |
| `lintCommand` | lint 명령 | `npm run lint` |
| `tscCommand` | 타입 체크 명령 | `npx tsc --noEmit` |
| `testFilePatterns` | 테스트 파일 탐색 패턴 | `["{dir}/__tests__/{name}.test.ts", ...]` |
| `protectedPaths` | 수정 차단 경로 | `[".env"]` |
| `trackDirs` | 변경 추적 디렉토리 | `["src"]` |

### 모노레포 예시

```json
{
  "srcDir": "packages/app/src",
  "testRunner": "pnpm vitest run",
  "testClientDir": "packages/app",
  "trackDirs": ["packages/app/src", "packages/shared/src"]
}
```

## 커스텀 커맨드

| 커맨드 | 역할 |
|---|---|
| `/plan` | 구현 전 계획 작성 → `.claude/plans/`에 저장 |
| `/done` | 품질 게이트 검증 → 계획 완료 → 커밋 메시지 생성 |

커맨드 내용은 `.claude/commands/`에서 수정할 수 있습니다.

## 에이전트

| 에이전트 | 역할 |
|---|---|
| `spec-writer` | 느슨한 명세 → 구체적 테크 스펙 문서 |
| `test-designer` | 테크 스펙 → 테스트 케이스 목록 설계 (코드 미작성) |
| `tdd-coder` | 테스트 설계서 → RED 테스트 작성 → GREEN 구현 |

에이전트 프롬프트는 `.claude/agents/`에서 프로젝트에 맞게 수정할 수 있습니다.

## .gitignore 권장

프로젝트 루트 `.gitignore`에 추가:

```
.claude/logs/
.claude/hooks/state/
.claude/hooks/*.log
.claude/plans/
```

## 요구사항

- Claude Code CLI
- `jq` (훅에서 JSON 파싱)
- Node.js (scope-guard.js)

## 라이선스

MIT
