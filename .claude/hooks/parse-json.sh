#!/usr/bin/env bash
# stdin에서 JSON을 읽고, 인자로 받은 경로의 값을 출력
# Usage: echo '{"a":{"b":"c"}}' | bash parse-json.sh a.b
#        → c
# jq 없이 Node.js로 동작

_PARSE_JSON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# stdin 캐싱 (한 훅에서 여러 필드를 읽을 때 재사용)
if [[ -z "${_HOOK_INPUT_CACHED:-}" ]]; then
  export _HOOK_INPUT_CACHED=$(cat)
fi

parse_json() {
  local json_path="$1"
  node -e "
    const d = JSON.parse(process.argv[1]);
    const keys = process.argv[2].split('.');
    let v = d;
    for (const k of keys) { v = v?.[k]; }
    if (v !== undefined && v !== null) process.stdout.write(String(v));
  " "$_HOOK_INPUT_CACHED" "$json_path" 2>/dev/null
}

parse_json_raw() {
  # JSON을 compact string으로 출력 (로그용)
  node -e "
    try { process.stdout.write(JSON.stringify(JSON.parse(process.argv[1]))); }
    catch(e) { process.stdout.write(process.argv[1]); }
  " "$_HOOK_INPUT_CACHED" 2>/dev/null
}
