#!/usr/bin/env node
/**
 * scope-guard.js의 "테스트 포함 여부" 강제 체크에 대한 self-check.
 * 프레임워크 없이 assert + child_process로 실제 scope-guard.js를 spawn해 검증한다.
 * 실행: node .claude/hooks/scope-guard.test.js
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const HOOKS_DIR = __dirname;
const PLANS_DIR = path.join(HOOKS_DIR, '../plans');
const SCOPE_GUARD = path.join(HOOKS_DIR, 'scope-guard.js');
const REPO_ROOT = path.join(HOOKS_DIR, '../..');
const TARGET_FILE = path.join(REPO_ROOT, 'src/zz-scope-guard-test-target.ts');
const TEST_PLAN_PATH = path.join(PLANS_DIR, 'zz-scope-guard-selftest.md');
const ACTIVE_PLAN_PATH = path.join(PLANS_DIR, 'zz-scope-guard-selftest-active.md');

function runScopeGuard(planBody) {
  fs.mkdirSync(PLANS_DIR, { recursive: true });
  fs.writeFileSync(TEST_PLAN_PATH, planBody);
  // 항상 최신으로 잡히도록 mtime을 미래로 고정
  const future = new Date(Date.now() + 60_000);
  fs.utimesSync(TEST_PLAN_PATH, future, future);

  const input = JSON.stringify({
    tool_name: 'Edit',
    tool_input: { file_path: TARGET_FILE },
  });
  return spawnSync('node', [SCOPE_GUARD], { input, encoding: 'utf8' });
}

function cleanup() {
  for (const p of [TEST_PLAN_PATH, ACTIVE_PLAN_PATH]) {
    if (fs.existsSync(p)) fs.unlinkSync(p);
  }
}

try {
  // 시나리오 1: "테스트 포함 여부" 섹션 자체가 없음 → 차단
  let result = runScopeGuard(`## 구현 계획: 테스트
### 구현 순서
1. src/zz-scope-guard-test-target.ts — 작업
`);
  assert.strictEqual(result.status, 2, '섹션 없으면 exit 2여야 함');
  assert.match(result.stderr, /테스트 포함 여부.*섹션이 없습니다/);

  // 시나리오 2: 섹션은 있지만 미답변(placeholder 그대로) → 차단
  result = runScopeGuard(`## 구현 계획: 테스트
### 테스트 포함 여부
- 포함: YES / NO
### 구현 순서
1. src/zz-scope-guard-test-target.ts — 작업
`);
  assert.strictEqual(result.status, 2, '미답변이면 exit 2여야 함');
  assert.match(result.stderr, /아직 결정되지 않았습니다/);

  // 시나리오 3: 명확히 답변(YES) + 파일이 계획에 있음 → 통과
  result = runScopeGuard(`## 구현 계획: 테스트
### 테스트 포함 여부
- 포함: YES
### 구현 순서
1. src/zz-scope-guard-test-target.ts — 작업
`);
  assert.strictEqual(result.status, 0, '답변되고 파일이 계획에 있으면 exit 0이어야 함');

  // 시나리오 4: 명확히 답변(NO) + 파일이 계획에 있음 → 통과
  result = runScopeGuard(`## 구현 계획: 테스트
### 테스트 포함 여부
- 포함: NO
### 구현 순서
1. src/zz-scope-guard-test-target.ts — 작업
`);
  assert.strictEqual(result.status, 0, 'NO로 답변되고 파일이 계획에 있으면 exit 0이어야 함');

  // 시나리오 5: 헤딩 문구가 본문 중간에 예시로도 등장 + 실제 헤딩에는 명확히 답변 → 통과
  // (split(heading)으로 구현했다가 실제로 걸렸던 회귀 케이스)
  result = runScopeGuard(`## 구현 계획: 테스트
설명 중간에 "### 테스트 포함 여부 / - 포함: YES / NO" 같은 예시 문구가 섞여 있어도
### 테스트 포함 여부
- 포함: YES
### 구현 순서
1. src/zz-scope-guard-test-target.ts — 작업
`);
  assert.strictEqual(result.status, 0, '본문 중 헤딩 예시 언급이 있어도 실제 헤딩의 답변으로 판단해야 함');

  // 시나리오 6: 옛 계획이 나중에 done 처리돼 mtime이 가장 최신이어도
  // 미완료 계획이 활성으로 선택돼야 함 (done 마커가 새 계획을 가리던 회귀 케이스)
  fs.writeFileSync(ACTIVE_PLAN_PATH, `## 구현 계획: 새 계획
### 테스트 포함 여부
- 포함: NO
### 구현 순서
1. src/zz-scope-guard-test-target.ts — 작업
`);
  const mid = new Date(Date.now() + 30_000);
  fs.utimesSync(ACTIVE_PLAN_PATH, mid, mid);
  result = runScopeGuard(`## 구현 계획: 옛 계획
## Status: done
`);
  assert.strictEqual(result.status, 0, 'mtime이 최신인 done 계획이 미완료 계획을 가리면 안 됨');

  console.log('✅ scope-guard 6개 시나리오 모두 통과');
} finally {
  cleanup();
}
