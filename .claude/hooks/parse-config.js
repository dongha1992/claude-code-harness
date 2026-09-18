#!/usr/bin/env node
/**
 * harness.config.json을 읽어 shell 변수 할당문을 stdout에 출력.
 * load-config.sh에서 eval "$(node parse-config.js)" 형태로 사용.
 */
const fs = require('fs');
const path = require('path');

const configPath = process.argv[2];
if (!configPath || !fs.existsSync(configPath)) {
  process.exit(0);
}

let config;
try {
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (e) {
  process.stderr.write(`[harness] Failed to parse config: ${e.message}\n`);
  process.exit(1);
}

// shell-safe 값 출력 (싱글 쿼트 이스케이프)
function q(v) {
  if (v === undefined || v === null) return "''";
  return "'" + String(v).replace(/'/g, "'\\''") + "'";
}

// tscCommand가 비었거나 "auto"면 tsconfig를 보고 결정한다.
// references 구조(루트 files: [])에서 `tsc --noEmit`은 아무것도 검사하지 않고 통과하므로 `tsc -b`를 쓴다.
function resolveTscCommand() {
  if (config.tscCommand && config.tscCommand !== 'auto') return config.tscCommand;
  const root = path.resolve(configPath, '../..');
  for (const dir of [config.testClientDir || '.', '.']) {
    const p = path.join(root, dir, 'tsconfig.json');
    if (!fs.existsSync(p)) continue;
    const text = fs.readFileSync(p, 'utf8').replace(/^\s*\/\/.*$/gm, '');
    return /"references"\s*:\s*\[\s*\{/.test(text) ? 'npx tsc -b' : 'npx tsc --noEmit';
  }
  return 'npx tsc --noEmit';
}
const values = { ...config, tscCommand: resolveTscCommand() };

// 키를 지정하면 해석된 값 하나만 출력 (예: /done이 실행할 명령 조회)
if (process.argv[3]) {
  process.stdout.write(String(values[process.argv[3]] ?? '') + '\n');
  process.exit(0);
}

const lines = [];

// 스칼라 값
const scalars = [
  'srcDir', 'testDir', 'testRunner', 'testRunnerArgs',
  'testClientDir', 'lintCommand', 'tscCommand',
  'lintDetectPattern', 'tscDetectPattern',
];
for (const key of scalars) {
  const envKey = 'CFG_' + key.replace(/[A-Z]/g, c => '_' + c).toUpperCase();
  lines.push(`${envKey}=${q(values[key] || '')}`);
}

// sourceExtensions → 파이프 연결
const exts = config.sourceExtensions || ['ts', 'tsx'];
lines.push(`CFG_SOURCE_EXTS=${q(exts.join('|'))}`);

// trackDirs → grep 패턴
const trackDirs = config.trackDirs || [];
lines.push(`CFG_TRACK_DIRS=${q(trackDirs.map(d => '^' + d).join('|'))}`);

// protectedPaths → 줄바꿈 구분 (bash에서 배열로 변환)
const protPaths = config.protectedPaths || [];
lines.push(`CFG_PROTECTED_PATHS_RAW=${q(protPaths.join('\n'))}`);

// testFilePatterns → 줄바꿈 구분
const testPatterns = config.testFilePatterns || [];
lines.push(`CFG_TEST_PATTERNS_RAW=${q(testPatterns.join('\n'))}`);

process.stdout.write(lines.join('\n') + '\n');
