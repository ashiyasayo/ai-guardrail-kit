#!/usr/bin/env bash
#
# smoke test：驗證 Copilot 版 sensitive-data-guard 兩個進入點的行為。
# 用法：bash tests/smoke_test.sh
#
# 【測試語料的寫法】本儲存庫自身啟用 integrated-harness，其 block_secrets 會攔截
# 含明文憑證的寫入、redact_sensitive_info 會「靜默改寫」含個資的寫入內容。若把
# 憑證與個資樣本以連續字面值寫在本檔中，寫入時會被攔截或被遮罩改寫，導致測試
# 語料失效而不易察覺。故所有敏感樣本一律以相鄰字串串接組出：檔案內容不含連續
# 字面值，執行期才組成完整樣本。
#
# 【斷言必須比對具體原因】「應被 deny」的斷言不可只比對 permissionDecision 為 deny：
# 任何普遍性的 deny（例如線路邊界誤擋）都會讓這類斷言全部假性通過，即使受測邏輯
# 完全失效也看不出來。decomposition-gate 的 smoke test 就曾因此在 Windows 上長期
# 假性通過。故此處一律比對各原因的專屬 ASCII 片段。
set -euo pipefail

# Windows（Git Bash）通常只有 python 而無 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks"
PRE_HOOK="$HOOKS_DIR/sensitive_data_guard.py"
PROMPT_HOOK="$HOOKS_DIR/block_pii_prompt.py"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# 供 JSON 使用的 cwd：Windows 上轉為原生路徑並轉義反斜線；POSIX 上原樣沿用。
# 本模式的 hook 不呼叫 project_root（個資與憑證掃描不需要檔案系統存取），故 cwd
# 只需通過「非空字串」驗證；此轉換是為了與 decomposition-gate 的測試保持一致，
# 並避免未來若加入路徑相關邏輯時重蹈該測試的覆轍。
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

# 敏感樣本（執行期串接，見檔頭說明）
SEC_AWS="AKIA""IOSFODNN7ABCDEFG"          # AWS Access Key 形態
PII_ID="A""123456789"                      # 台灣身分證字號形態
PII_MOBILE="0912""345678"                  # 手機號碼形態
PII_EMAIL="user""@example.org"             # Email 形態
PII_CARD="4111""111111111111"              # 通過 Luhn 的信用卡卡號形態
NOT_CARD="1234""567890123456"              # 未通過 Luhn 的長數字（應放行）

# 產生一份欄位完整的 VS Code PreToolUse 事件；$1 工具名、$2 tool_input(JSON)
evt_pre() {
  printf '{"hook_event_name":"PreToolUse","session_id":"s","transcript_path":"t","tool_name":"%s","tool_input":%s,"tool_use_id":"u","cwd":"%s"}' "$1" "$2" "$CWD_JSON"
}

# 產生一份 UserPromptSubmit 事件；$1 提示內容
evt_prompt() {
  printf '{"hook_event_name":"UserPromptSubmit","session_id":"s","transcript_path":"t","prompt":"%s","cwd":"%s"}' "$1" "$CWD_JSON"
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

# 各 deny 原因的專屬 ASCII 片段（互相排斥，可區分是哪一道檢查擋的）
SECRET_HIT='Secret blocked'
PII_HIT='Personal data blocked'
BAD_INPUT='Invalid Copilot hook input'
EVENT_PRE='"hookEventName": "PreToolUse"'
EVENT_PROMPT='"hookEventName": "UserPromptSubmit"'

echo "== 線路邊界（PreToolUse）=="

echo "情境 1：輸入非法 JSON → deny"
out=$(printf 'not json' | python3 "$PRE_HOOK")
check_contains "非法 JSON 被 deny" "$BAD_INPUT" "$out"

echo "情境 2：缺必填欄位（無 cwd）→ deny"
out=$(printf '{"hook_event_name":"PreToolUse","session_id":"s","transcript_path":"t","tool_name":"create_file","tool_input":{},"tool_use_id":"u"}' | python3 "$PRE_HOOK")
check_contains "缺欄位被 deny" "$BAD_INPUT" "$out"

echo "情境 3：hook_event_name 不符 → deny"
out=$(printf '{"hook_event_name":"PostToolUse","session_id":"s","transcript_path":"t","tool_name":"create_file","tool_input":{},"tool_use_id":"u","cwd":"%s"}' "$CWD_JSON" | python3 "$PRE_HOOK")
check_contains "錯誤事件名被 deny" "$BAD_INPUT" "$out"

echo "== 憑證阻擋 =="

echo "情境 4：create_file 內容含憑證 → deny"
out=$(evt_pre "create_file" "{\"filePath\":\"a.py\",\"content\":\"key = '$SEC_AWS'\"}" | python3 "$PRE_HOOK")
check_contains "create_file 憑證被擋" "$SECRET_HIT" "$out"

echo "情境 5：run_in_terminal 指令含憑證 → deny"
out=$(evt_pre "run_in_terminal" "{\"command\":\"echo $SEC_AWS\"}" | python3 "$PRE_HOOK")
check_contains "terminal 憑證被擋" "$SECRET_HIT" "$out"

echo "情境 6：multi_replace 的 newString 含憑證 → deny（證明遞迴掃描不依賴欄位名）"
out=$(evt_pre "multi_replace_string_in_file" "{\"replacements\":[{\"filePath\":\"a.py\",\"oldString\":\"x\",\"newString\":\"$SEC_AWS\"}]}" | python3 "$PRE_HOOK")
check_contains "multi_replace 憑證被擋" "$SECRET_HIT" "$out"

echo "情境 7：佔位符憑證應放行（無輸出）"
out=$(evt_pre "create_file" '{"filePath":"a.py","content":"api_key = \"YOUR_API_KEY_HERE\""}' | python3 "$PRE_HOOK")
check_empty "佔位符放行" "$out"

echo "== 個資阻擋（deny，不做遮罩改寫）=="

echo "情境 8：create_file 內容含身分證字號 → deny"
out=$(evt_pre "create_file" "{\"filePath\":\"a.txt\",\"content\":\"$PII_ID\"}" | python3 "$PRE_HOOK")
check_contains "身分證被擋" "$PII_HIT" "$out"

echo "情境 9：run_in_terminal 指令含個資 → deny（Claude 版刻意不掃 Bash，此處為刻意分歧）"
out=$(evt_pre "run_in_terminal" "{\"command\":\"echo $PII_ID > out.txt\"}" | python3 "$PRE_HOOK")
check_contains "terminal 個資被擋" "$PII_HIT" "$out"

echo "情境 10：個資只出現在 filePath 也會被擋（證明遞迴掃描涵蓋全部欄位）"
out=$(evt_pre "create_file" "{\"filePath\":\"$PII_MOBILE.txt\",\"content\":\"ok\"}" | python3 "$PRE_HOOK")
check_contains "filePath 個資被擋" "$PII_HIT" "$out"

echo "情境 11：Email 應被擋"
out=$(evt_pre "create_file" "{\"filePath\":\"a.txt\",\"content\":\"$PII_EMAIL\"}" | python3 "$PRE_HOOK")
check_contains "Email 被擋" "$PII_HIT" "$out"

echo "情境 12：通過 Luhn 的卡號應被擋"
out=$(evt_pre "create_file" "{\"filePath\":\"a.txt\",\"content\":\"$PII_CARD\"}" | python3 "$PRE_HOOK")
check_contains "卡號被擋" "$PII_HIT" "$out"

echo "情境 13：未通過 Luhn 的長數字應放行（無輸出）"
out=$(evt_pre "create_file" "{\"filePath\":\"a.txt\",\"content\":\"$NOT_CARD\"}" | python3 "$PRE_HOOK")
check_empty "Luhn 不符放行" "$out"

echo "情境 14：乾淨內容應放行（無輸出）"
out=$(evt_pre "create_file" '{"filePath":"a.py","content":"print(1)"}' | python3 "$PRE_HOOK")
check_empty "乾淨內容放行" "$out"

echo "== 涵蓋範圍與輸出鐵律 =="

echo "情境 15：未知工具攜帶憑證仍被擋（與 decomposition-gate 的未知工具放行刻意不同）"
out=$(evt_pre "some_future_tool" "{\"payload\":\"$SEC_AWS\"}" | python3 "$PRE_HOOK")
check_contains "未知工具憑證被擋" "$SECRET_HIT" "$out"

echo "情境 16：唯讀工具且內容乾淨應放行（無輸出）"
out=$(evt_pre "read_file" '{"filePath":"a.py"}' | python3 "$PRE_HOOK")
check_empty "唯讀工具放行" "$out"

echo "情境 17：憑證檢查優先於個資檢查（同時含兩者時回報憑證）"
out=$(evt_pre "create_file" "{\"filePath\":\"a.txt\",\"content\":\"$SEC_AWS and $PII_ID\"}" | python3 "$PRE_HOOK")
check_contains "憑證優先" "$SECRET_HIT" "$out"

echo "情境 18：deny 輸出必須是純 ASCII（否則 VS Code 判 non-JSON 而 fail-open）"
out=$(evt_pre "create_file" "{\"filePath\":\"a.txt\",\"content\":\"$PII_ID\"}" | python3 "$PRE_HOOK")
if printf '%s' "$out" | LC_ALL=C grep -q '[^ -~]'; then
  echo "  FAIL: 輸出含非 ASCII 位元組"; echo "    actual: $out"; fail=$((fail + 1))
else
  echo "  PASS: 輸出為純 ASCII"; pass=$((pass + 1))
fi

echo "情境 19：deny 輸出的事件名為 PreToolUse"
check_contains "PreToolUse 事件名正確" "$EVENT_PRE" "$out"

echo "== UserPromptSubmit（提示詞個資阻擋；輸出形狀未實機驗證）=="

echo "情境 20：提示含個資 → 阻擋"
out=$(evt_prompt "customer id is $PII_ID" | python3 "$PROMPT_HOOK")
check_contains "提示個資被擋" "$PII_HIT" "$out"

echo "情境 21：阻擋輸出的事件名為 UserPromptSubmit（形狀必須與事件相符）"
check_contains "UserPromptSubmit 事件名正確" "$EVENT_PROMPT" "$out"

echo "情境 22：乾淨提示應放行（無輸出）"
out=$(evt_prompt "please refactor this function" | python3 "$PROMPT_HOOK")
check_empty "乾淨提示放行" "$out"

echo "情境 23：提示含憑證不阻擋（模式邊界：提示只擋個資）"
out=$(evt_prompt "my key is $SEC_AWS" | python3 "$PROMPT_HOOK")
check_empty "提示憑證不擋" "$out"

echo "情境 24：UserPromptSubmit 收到非法 JSON → 以 UserPromptSubmit 形狀阻擋"
out=$(printf 'not json' | python3 "$PROMPT_HOOK")
check_contains "非法 JSON 被擋" "$BAD_INPUT" "$out"
check_contains "錯誤路徑事件名正確" "$EVENT_PROMPT" "$out"

echo "情境 25：缺 prompt 欄位 → 以 UserPromptSubmit 形狀阻擋"
out=$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"s"}' | python3 "$PROMPT_HOOK")
check_contains "缺 prompt 被擋" "$BAD_INPUT" "$out"
check_contains "缺欄位事件名正確" "$EVENT_PROMPT" "$out"

echo
echo "結果：$pass 通過，$fail 失敗"
[ "$fail" -eq 0 ]
