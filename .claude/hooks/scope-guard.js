#!/usr/bin/env node
/**
 * PreToolUse 훅: Edit/Write 시도 시 활성 계획 파일과 대조
 *
 * exit 0 → 허용
 * exit 2 → Claude Code가 툴 호출 차단 + stderr 내용을 Claude에게 피드백
 *
 * 동작 원칙:
 * - .claude/ 내부 수정은 항상 허용 (계획 파일 저장 등)
 * - 활성 계획 파일이 없으면 제한 없음 (LOW 작업)
 * - 계획에 없는 파일은 src/ 포함 전부 차단 (exit 2)
 */

const fs   = require('fs');
const path = require('path');

// stdin에서 PreToolUse 훅 데이터 읽기
let hookData = {};
try {
  const raw = fs.readFileSync('/dev/stdin', 'utf8');
  hookData = JSON.parse(raw);
} catch (_) {
  process.exit(0);
}

const toolName  = hookData.tool_name ?? '';
const toolInput = hookData.tool_input ?? {};

// Edit, Write 툴만 검사
if (!['Edit', 'Write'].includes(toolName)) process.exit(0);

const targetFile  = toolInput.file_path ?? '';
if (!targetFile) process.exit(0);

// 스크립트 위치(tulip/.claude/hooks/) 기준으로 repo root 결정
// → cwd가 client/ 등 하위 디렉토리여도 올바른 경로를 참조한다
const projectRoot = path.join(__dirname, '../..');
// OS 무관하게 슬래시로 정규화
const relativePath = path.relative(projectRoot, targetFile).split(path.sep).join('/');

// .claude/ 내부는 항상 허용 (계획 저장, 커맨드 수정 등)
if (relativePath.startsWith('.claude/')) process.exit(0);

// 활성 계획 파일 탐색 (.claude/plans/ 내 가장 최근 .md)
const plansDir = path.join(__dirname, '../plans');
let planFiles = [];
try {
  planFiles = fs.readdirSync(plansDir)
    .filter(f => f.endsWith('.md') && f !== '.gitkeep')
    .sort((a, b) => {
      const mtimeA = fs.statSync(path.join(plansDir, a)).mtimeMs;
      const mtimeB = fs.statSync(path.join(plansDir, b)).mtimeMs;
      return mtimeA - mtimeB;
    });
} catch (_) {}

// 계획 파일 없으면 차단 (먼저 /plan 실행 필요)
if (planFiles.length === 0) {
  const msg = '[scope-guard] 활성 계획 파일이 없습니다. /plan을 먼저 실행하세요.';
  process.stdout.write(msg + '\n');
  process.stderr.write(msg + '\n');
  process.exit(2);
}

const latestPlanPath = path.join(plansDir, planFiles.at(-1));
let latestPlan = '';
try {
  latestPlan = fs.readFileSync(latestPlanPath, 'utf8');
} catch (_) {
  process.exit(0);
}

// 완료된 계획 → 차단 (새 /plan 요구)
if (/^##\s*Status:\s*done/im.test(latestPlan)) {
  const msg = `[scope-guard] 최신 계획(${planFiles.at(-1)})이 완료 상태입니다. 새 /plan을 먼저 실행하세요.`;
  process.stdout.write(msg + '\n');
  process.stderr.write(msg + '\n');
  process.exit(2);
}

// 계획 파일에 현재 파일이 언급됐는지 확인 (suffix 매칭)
// client/src/, crawler/, mcp/ 등 패키지 prefix와 무관하게 동작한다
const pathParts = relativePath.split('/');
const isInPlan = pathParts.some((_, i) =>
  latestPlan.includes(pathParts.slice(i).join('/'))
);

if (isInPlan) process.exit(0);

// 계획에 없는 파일 — 경로 무관하게 전부 차단
const message = [
  `[scope-guard] 계획에 없는 파일 수정 시도: ${relativePath}`,
  `활성 계획: ${planFiles.at(-1)}`,
  '계획 파일의 "구현 순서"에 이 파일을 추가하거나, /plan을 먼저 실행하세요.',
].join('\n');

process.stdout.write(message + '\n');
process.stderr.write(message + '\n');
process.exit(2);
