#!/usr/bin/env bash
#
# smoke test：驗證 Copilot 版 decomposition_gate.py 在各情境下的行為。
# 用法：bash tests/smoke_test.sh
#
# 【Windows 路徑陷阱】Git Bash 會把 POSIX 路徑「參數」轉換成 Windows 路徑再交給原生
# 執行檔，但**不會**轉換經由 stdin 傳入的內容。本測試的 cwd 是放在 JSON 裡經 stdin
# 傳給 hook，因此原生 Windows Python 會收到字面的 /tmp/tmp.XXXX，並將其解析為當前
# 磁碟根目錄下的 \tmp\tmp.XXXX（不存在）→ project_root() 一律 deny。
# 故 cwd 必須先以 cygpath 轉為 Windows 路徑，並把反斜線轉義成 JSON 合法形式。
#
# 【斷言必須比對具體原因】若「應被 deny」的斷言只比對 permissionDecision 為 deny，
# 上述路徑錯誤造成的普遍性 deny 會讓這些斷言全部假性通過——即使 gate 邏輯完全失效
# 也看不出來。輸出為 ASCII 轉義 JSON（中文會變成 \uXXXX），故改以各原因中可辨識的
# ASCII 片段比對。
set -euo pipefail

# Windows（Git Bash）通常只有 python 而無 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/decomposition_gate.py"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

PLAN_DIR="$WORKDIR/.github/guardrail/plan"
PLAN_FILE="$PLAN_DIR/decomposition.md"
mkdir -p "$PLAN_DIR"

# 供 JSON 使用的 cwd：Windows 上轉為原生路徑並轉義反斜線；POSIX 上原樣沿用
to_json_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    path="$(cygpath -w "$path")"
    path="${path//\\/\\\\}"
  fi
  printf '%s' "$path"
}
CWD_JSON="$(to_json_path "$WORKDIR")"

pass=0
fail=0

# 產生一份欄位完整的 VS Code PreToolUse 事件；$1 工具名、$2 tool_input(JSON)
# 注意：filePath 維持 POSIX 形式——受測程式以 path.replace("\\", "/") 正規化後
# 才與 PLAN 比對，只有 cwd 需要真實可解析的原生路徑。
evt() {
  printf '{"hook_event_name":"PreToolUse","session_id":"s","transcript_path":"t","tool_name":"%s","tool_input":%s,"tool_use_id":"u","cwd":"%s"}' "$1" "$2" "$CWD_JSON"
}

# 寫入一份完整（含全部標記）的拆解檔
write_complete_plan() {
  cat > "$PLAN_FILE" <<'EOF'
# 任務拆解
## 已知資訊
- x
## 缺少的資訊
- y
## 假設
- 【假設】z
EOF
}

# 寫入一份缺標記的拆解檔
write_incomplete_plan() {
  cat > "$PLAN_FILE" <<'EOF'
# 任務拆解
## 已知資訊
- x
EOF
}

check_contains() {
  local name="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $name"; pass=$((pass + 1))
  else
    echo "  FAIL: $name"; echo "    expected to contain: $expected"; echo "    actual: $actual"; fail=$((fail + 1))
  fi
}

check_empty() {
  local name="$1" actual="$2"
  if [ -z "$actual" ]; then
    echo "  PASS: $name"; pass=$((pass + 1))
  else
    echo "  FAIL: $name"; echo "    expected empty output, actual: $actual"; fail=$((fail + 1))
  fi
}

# 各 deny 原因中可辨識的 ASCII 片段（互相排斥，可區分是哪一道關卡擋的）
BAD_INPUT='Invalid Copilot hook input'
PLAN_GATE='Plan gate:'
BYPASS_GUARD='\.gate_disabled'

echo "== 線路邊界（hook_protocol）=="

echo "情境 1：輸入非法 JSON → deny"
out=$(printf 'not json' | python3 "$HOOK")
check_contains "非法 JSON 被 deny" "$BAD_INPUT" "$out"

echo "情境 2：缺必填欄位（無 cwd）→ deny"
out=$(printf '{"hook_event_name":"PreToolUse","session_id":"s","transcript_path":"t","tool_name":"read_file","tool_input":{},"tool_use_id":"u"}' | python3 "$HOOK")
check_contains "缺欄位被 deny" "$BAD_INPUT" "$out"

echo "情境 3：hook_event_name 非 PreToolUse → deny"
out=$(printf '{"hook_event_name":"PostToolUse","session_id":"s","transcript_path":"t","tool_name":"read_file","tool_input":{},"tool_use_id":"u","cwd":"%s"}' "$CWD_JSON" | python3 "$HOOK")
check_contains "錯誤事件名被 deny" "$BAD_INPUT" "$out"

echo "== 檔案寫入向量 =="

echo "情境 4：唯讀 read_file 應放行（無輸出）"
out=$(evt "read_file" '{"filePath":"a.py"}' | python3 "$HOOK")
check_empty "read_file 放行" "$out"

echo "情境 5：無拆解檔時 create_file 應被 deny"
out=$(evt "create_file" '{"filePath":"src/main.py","content":"x"}' | python3 "$HOOK")
check_contains "create_file 被封鎖" "$PLAN_GATE" "$out"

echo "情境 6：撰寫拆解檔本身應放行（無輸出）"
out=$(evt "create_file" "{\"filePath\":\"$WORKDIR/.github/guardrail/plan/decomposition.md\",\"content\":\"x\"}" | python3 "$HOOK")
check_empty "拆解檔寫入放行" "$out"

echo "情境 7：拆解檔完整後 create_file 應放行（無輸出）"
write_complete_plan
out=$(evt "create_file" '{"filePath":"src/main.py","content":"x"}' | python3 "$HOOK")
check_empty "關卡通過後放行" "$out"

echo "情境 8：拆解檔缺標記時 create_file 應被 deny"
write_incomplete_plan
out=$(evt "create_file" '{"filePath":"src/main.py","content":"x"}' | python3 "$HOOK")
check_contains "缺標記被封鎖" "$PLAN_GATE" "$out"

echo "情境 9：無/不完整拆解檔時 multi_replace_string_in_file 應被 deny"
out=$(evt "multi_replace_string_in_file" '{"replacements":[{"filePath":"src/main.py","oldString":"a","newString":"b"}]}' | python3 "$HOOK")
check_contains "multi_replace 被封鎖" "$PLAN_GATE" "$out"

echo "== run_in_terminal 整體 gate =="

echo "情境 10：無拆解檔時 run_in_terminal（含唯讀 git status）應被 deny"
rm -f "$PLAN_FILE"
out=$(evt "run_in_terminal" '{"command":"git status"}' | python3 "$HOOK")
check_contains "terminal 整體封鎖" "$PLAN_GATE" "$out"

echo "情境 11：拆解檔完整後 run_in_terminal 應放行（無輸出）"
write_complete_plan
out=$(evt "run_in_terminal" '{"command":"echo hi > note.txt"}' | python3 "$HOOK")
check_empty "關卡通過後 terminal 放行" "$out"

echo "== 逃生口保護（拆解檔完整仍不得自建 .gate_disabled）=="
write_complete_plan

echo "情境 12：create_file 建立 .gate_disabled 應被 deny"
out=$(evt "create_file" '{"filePath":".github/guardrail/plan/.gate_disabled","content":""}' | python3 "$HOOK")
check_contains "create_file 逃生口被封鎖" "$BYPASS_GUARD" "$out"

echo "情境 13：run_in_terminal 內含 .gate_disabled 應被 deny"
out=$(evt "run_in_terminal" '{"command":"touch .github/guardrail/plan/.gate_disabled"}' | python3 "$HOOK")
check_contains "terminal 逃生口被封鎖" "$BYPASS_GUARD" "$out"

echo "情境 14：multi_replace 寫 .gate_disabled 應被 deny"
out=$(evt "multi_replace_string_in_file" '{"replacements":[{"filePath":".github/guardrail/plan/.gate_disabled","oldString":"","newString":"x"}]}' | python3 "$HOOK")
check_contains "multi_replace 逃生口被封鎖" "$BYPASS_GUARD" "$out"

echo "== 逃生口生效 / 未知工具 =="

echo "情境 15：逃生口存在時，無拆解檔 create_file 也放行（無輸出）"
rm -f "$PLAN_FILE"
touch "$PLAN_DIR/.gate_disabled"
out=$(evt "create_file" '{"filePath":"src/main.py","content":"x"}' | python3 "$HOOK")
check_empty "逃生口生效放行" "$out"
rm -f "$PLAN_DIR/.gate_disabled"

echo "情境 16：未知工具應放行（無輸出，決策 2A）"
out=$(evt "some_future_tool" '{"foo":"bar"}' | python3 "$HOOK")
check_empty "未知工具放行" "$out"

echo
echo "結果：$pass 通過，$fail 失敗"
[ "$fail" -eq 0 ]
