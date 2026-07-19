#!/usr/bin/env bash
set -euo pipefail
# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/.claude/plan"
export CLAUDE_PROJECT_DIR="$WORKDIR"
PLAN="$ROOT/.claude/hooks/plan_gate.py"
SECRET="$ROOT/.claude/hooks/block_secrets.py"
DANGER="$ROOT/.claude/hooks/block_dangerous_commands.py"
APPROVE="$ROOT/.claude/hooks/approve_plan.py"
pass=0
fail=0

check() {
  local name="$1" expected="$2" actual="$3"
  if printf '%s\n' "$actual" | grep -q "$expected"; then
    printf 'PASS: %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL: %s\n  actual: %s\n' "$name" "$actual"
    fail=$((fail + 1))
  fi
}

record_pass() {
  printf 'PASS: %s\n' "$1"
  pass=$((pass + 1))
}

record_fail() {
  printf 'FAIL: %s\n  actual: %s\n' "$1" "$2"
  fail=$((fail + 1))
}

check_allow() {
  local name="$1" actual="$2"
  if [ -z "$actual" ]; then
    record_pass "$name"
  else
    record_fail "$name" "$actual"
  fi
}

check_deny() {
  local name="$1" actual="$2" reason_pattern="${3:-}"
  if python3 - "$actual" "$reason_pattern" <<'PY'
import json
import re
import sys

payload = json.loads(sys.argv[1])
output = payload["hookSpecificOutput"]
assert output["hookEventName"] == "PreToolUse"
assert output["permissionDecision"] == "deny"
if sys.argv[2]:
    assert re.search(sys.argv[2], output["permissionDecisionReason"])
PY
  then
    record_pass "$name"
  else
    record_fail "$name" "$actual"
  fi
}

run_hook() { printf '%s' "$2" | python3 "$1"; }

write_basic_plan() {
  cat > "$WORKDIR/.claude/plan/decomposition.md" <<'EOF'
## 已知資訊
- 已確認測試工作目錄。
## 缺少的資訊
- 無。
## 假設
- 【假設】測試只操作暫存目錄。
EOF
}

write_scoped_plan() {
  cat > "$WORKDIR/.claude/plan/decomposition.md" <<'EOF'
## 已知資訊
- 已確認測試工作目錄。
## 缺少的資訊
- 無。
## 假設
- 【假設】測試只操作暫存目錄。
## 允許修改範圍
- `src/a.py`
- `tests/fixtures/`
EOF
}

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"git status"}}')"
check_allow "唯讀 Bash 放行" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_deny "無拆解時拒絕寫入" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":".claude/plan/decomposition.md","content":"x"}}')"
check_allow "允許撰寫拆解" "$out"

for tool in EnterPlanMode LSP TaskGet TaskList TaskOutput CronList ListMcpResourcesTool ReadMcpResourceTool ToolSearch WaitForMcpServers; do
  out="$(run_hook "$PLAN" "{\"tool_name\":\"$tool\",\"tool_input\":{}}")"
  check_allow "無拆解時放行 pre-plan safe tool：$tool" "$out"
done

out="$(run_hook "$PLAN" '{"tool_name":"SomeMutatingTool","tool_input":{"value":"x"}}')"
check_deny "未知工具不得繞過計畫" "$out" '找不到拆解文件'

out="$(run_hook "$PLAN" '{"tool_name":"Agent","tool_input":{"prompt":"修改程式"}}')"
check_deny "派工前必須完成計畫" "$out" '找不到拆解文件'

write_basic_plan
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_deny "strict 要求允許修改範圍" "$out" '允許修改範圍'

write_scoped_plan
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_deny "有拆解但未核准仍拒絕" "$out" '尚未取得人類核准'

python3 "$APPROVE" >/dev/null
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_allow "完整拆解及核准後放行" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_allow "精確檔案範圍放行" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Edit","tool_input":{"file_path":"tests/fixtures/a.txt","new_string":"x"}}')"
check_allow "目錄範圍放行" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/b.py","content":"x"}}')"
check_deny "範圍外檔案拒絕" "$out" '不在計畫允許修改範圍'

out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"../outside.txt","content":"x"}}')"
check_deny "專案外路徑拒絕" "$out" '不在計畫允許修改範圍'

cat > "$WORKDIR/.claude/orchestration-policy.md" <<'EOF'
## 核准模式
- 核准模式：strict

## Strict Bash 測試與建置 Allowlist
- `bash tests/`
- `dotnet test`
- `dotnet build`
- `npm test`
- `npm run build`
EOF
mkdir -p "$WORKDIR/tests"
printf '#!/usr/bin/env bash\n' > "$WORKDIR/tests/smoke_test.sh"
python3 "$APPROVE" >/dev/null

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"touch output.txt"}}')"
check_deny "strict 拒絕一般 Bash" "$out" 'strict.*Bash'

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"npm test -- --runInBand"}}')"
check_allow "strict 放行 allowlist 測試命令" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"npm run build"}}')"
check_allow "strict 放行 allowlist 建置命令" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"bash tests/smoke_test.sh"}}')"
check_allow "strict 放行 tests 目錄腳本" "$out"

rm -f "$WORKDIR/.claude/.plan_approved"
out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"npm test"}}')"
check_deny "strict allowlist 命令仍須人工核准" "$out" '尚未取得人類核准'
python3 "$APPROVE" >/dev/null

for command in \
  'npm test && touch escaped' \
  'npm test > result.txt' \
  'npm test $(touch escaped)' \
  'TOKEN=x npm test' \
  'npm testing' \
  'bash tests/../outside.sh' \
  'bash /tmp/outside.sh'; do
  payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")"
  out="$(run_hook "$PLAN" "$payload")"
  check_deny "strict allowlist 拒絕：$command" "$out" 'strict.*Bash'
done

cat > "$WORKDIR/.claude/orchestration-policy.md" <<'EOF'
## 核准模式
- 核准模式：strict
EOF
out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"npm test"}}')"
check_deny "strict 缺少 allowlist section 時保守拒絕" "$out" '缺少 strict Bash 測試與建置 allowlist'

cat > "$WORKDIR/.claude/orchestration-policy.md" <<'EOF'
## 核准模式
- 核准模式：strict

## Strict Bash 測試與建置 Allowlist
- npm test
EOF
out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"npm test"}}')"
check_deny "strict 非反引號 allowlist item 時保守拒絕" "$out" '必須使用反引號 Markdown 清單'

cat > "$WORKDIR/.claude/orchestration-policy.md" <<'EOF'
## 核准模式
- 核准模式：strict

## Strict Bash 測試與建置 Allowlist
EOF
out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"npm test"}}')"
check_deny "strict 空 allowlist 時保守拒絕" "$out" '至少需要一個測試或建置命令'

rm -f "$WORKDIR/.claude/.plan_approved"
cat > "$WORKDIR/.claude/orchestration-policy.md" <<'EOF'
- 核准模式：standard
EOF
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_allow "standard 範圍內免人工核准" "$out"
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/b.py","content":"x"}}')"
check_deny "standard 仍限制修改範圍" "$out" '不在計畫允許修改範圍'
out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"touch output.txt"}}')"
check_allow "standard 計畫通過後放行一般 Bash" "$out"

cat > "$WORKDIR/.claude/orchestration-policy.md" <<'EOF'
- 核准模式：light
EOF
out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"touch output.txt"}}')"
check_allow "light 計畫通過後放行一般 Bash" "$out"
rm -f "$WORKDIR/.claude/orchestration-policy.md"

python3 "$APPROVE" >/dev/null

out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":".claude/.plan_approved","content":"x"}}')"
check_deny "禁止工具自我核准" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"touch .claude/.plan_approved"}}')"
check_deny "禁止 Bash 自我核准" "$out"

printf '\n- changed\n' >> "$WORKDIR/.claude/plan/decomposition.md"
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_deny "核准後修改計畫須重審" "$out" '核准版本不一致'

rm -f "$WORKDIR/.claude/.plan_approved"
out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"env touch /tmp/gate-bypass"}}')"
check_deny "env 不得偽裝成唯讀命令" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"find . -fprintf /tmp/find-output x"}}')"
check_deny "find 寫入參數不得放行" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"git branch -D main"}}')"
check_deny "git branch 變更參數不得放行" "$out"

python3 "$APPROVE" >/dev/null
out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"touch .claude/.plan*"}}')"
check_deny "禁止 glob 延長核准" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"sed -i.bak s/strict/light/ .claude/orchestration-polic?.md"}}')"
check_deny "禁止 glob 修改政策" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"NotebookEdit","tool_input":{"new_source":"password = \"P4ssw0rd88abc\""}}')"
check_deny "NotebookEdit 憑證攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Write","tool_input":{"content":"api_key = \"${API_KEY}\""}}')"
check_allow "環境變數佔位符放行" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Write","tool_input":{"content":"password = \"realPLACEHOLDERsecret\""}}')"
check_deny "placeholder 子字串不得掩蓋真憑證" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Write","tool_input":{"content":"password = \"YOUR_PASSWORD\""}}')"
check_allow "完整 placeholder 仍放行" "$out"

for payload in \
  '{"tool_name":"Write","tool_input":{}}' \
  '{"tool_name":"Edit","tool_input":{"new_string":42}}' \
  '{"tool_name":"MultiEdit","tool_input":{"edits":"bad"}}' \
  '{"tool_name":"MultiEdit","tool_input":{"edits":[{"old_string":"x"}]}}' \
  '{"tool_name":"NotebookEdit","tool_input":{"new_source":[]}}' \
  '{"tool_name":"Bash","tool_input":{"command":false}}'; do
  set +e
  out="$(run_hook "$SECRET" "$payload" 2>&1)"
  status=$?
  set -e
  check "已知工具 schema 不符回報錯誤" 'schema 不符' "$out"
  check "已知工具 schema 不符使用阻擋狀態" '^2$' "$status"
done

for payload in \
  '[]' \
  '{"tool_name":[],"tool_input":{}}'; do
  set +e
  out="$(run_hook "$SECRET" "$payload" 2>&1)"
  status=$?
  set -e
  check "secret hook envelope schema 不符回報錯誤" 'schema 不符' "$out"
  check "secret hook envelope schema 不符使用阻擋狀態" '^2$' "$status"
done

for payload in \
  '{"tool_name":"Write","tool_input":{"content":"safe"}}' \
  '{"tool_name":"Edit","tool_input":{"new_string":"safe"}}' \
  '{"tool_name":"MultiEdit","tool_input":{"edits":[{"new_string":"safe"}]}}' \
  '{"tool_name":"NotebookEdit","tool_input":{"new_source":"safe"}}' \
  '{"tool_name":"Bash","tool_input":{"command":"printf safe"}}'; do
  out="$(run_hook "$SECRET" "$payload")"
  check_allow "已知工具正常 schema 放行" "$out"
done

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"printf secret > config.py; password=\"RealSecret12345\""}}')"
check_deny "Bash 明顯憑證攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=\"${DB_PASSWORD}\" ./run.sh"}}')"
check_allow "Bash 環境變數佔位符放行" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=RealSecret12345 ./run.sh"}}')"
check_deny "Bash 未引號憑證攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"export password=RealSecret12345 ./run.sh"}}')"
check_deny "Bash export 未引號憑證攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=$DB_PASSWORD ./run.sh"}}')"
check_allow "Bash dollar 環境變數放行" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=${DB_PASSWORD} ./run.sh"}}')"
check_allow "Bash braced 環境變數放行" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=YOUR_PASSWORD ./run.sh"}}')"
check_allow "Bash 既有文字佔位符放行" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=${DB_PASSWORD:-RealSecret12345} ./run.sh"}}')"
check_deny "Bash parameter expansion hard-coded fallback 攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=\"${DB_PASSWORD:-RealSecret12345}\" ./run.sh"}}')"
check_deny "Bash quoted parameter expansion hard-coded fallback 攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=${DB_PASSWORD:=RealSecret12345} ./run.sh"}}')"
check_deny "Bash parameter expansion hard-coded assignment fallback 攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=\"${DB_PASSWORD:=RealSecret12345}\" ./run.sh"}}')"
check_deny "Bash quoted parameter expansion hard-coded assignment fallback 攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=${DB_PASSWORD:-YOUR_PASSWORD} ./run.sh"}}')"
check_allow "Bash parameter expansion placeholder fallback 放行" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=${A:-YOUR_PASSWORD}; api_key=${B:-RealSecret12345}"}}')"
check_deny "後續 parameter fallback 真憑證攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=\"YOUR_PASSWORD\"; api_key=\"RealSecret12345\""}}')"
check_deny "後續 quoted 真憑證攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=$A; api_key=RealSecret12345"}}')"
check_deny "後續 unquoted 真憑證攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=YOUR_PASSWORD; api_key=RealSecret12345"}}')"
check_deny "首項為明確 placeholder 的後續 unquoted 真憑證攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Bash","tool_input":{"command":"password=${A:-YOUR_PASSWORD}; api_key=\"CHANGE_ME\"; secret=$C"}}')"
check_allow "多個純 reference 與明確 placeholder 放行" "$out"

set +e
out="$(printf '{' | python3 "$SECRET" 2>&1)"
status=$?
set -e
check "malformed secret 輸入回報錯誤" '無法解析 hook 輸入' "$out"
check "malformed secret 輸入使用阻擋狀態" '^2$' "$status"

set +e
out="$(printf '{' | python3 "$PLAN" 2>&1)"
status=$?
set -e
check "malformed plan 輸入回報錯誤" '無法解析 hook 輸入' "$out"
check "malformed plan 輸入使用阻擋狀態" '^2$' "$status"

set +e
out="$(printf '{' | python3 "$DANGER" 2>&1)"
status=$?
set -e
check "malformed danger 輸入回報錯誤" '無法解析 hook 輸入' "$out"
check "malformed danger 輸入使用阻擋狀態" '^2$' "$status"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}')"
check_deny "危險命令永久攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"rm -r -f build"}}')"
check_deny "rm 分離旗標仍攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"/bin/rm -rf build"}}')"
check_deny "rm 絕對路徑仍攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git -C . reset --hard"}}')"
check_deny "git 全域參數後硬重置仍攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git filter-branch -- --all"}}')"
check_deny "清空 Git 歷史攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"systemctl disable crowdstrike"}}')"
check_deny "停用安全服務攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"cat /etc/shadow"}}')"
check_deny "系統帳密檔攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"echo \"rm -rf /\""}}')"
check_allow "引用危險命令文字不誤判" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main:refs/heads/main2"}}')"
check_allow "非保護目的 ref 不誤判" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"rm -rf \"unterminated"}}')"
check_deny "tokenization 失敗仍使用 raw fallback" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Write","tool_input":{"content":"cloudflare_api_token = \"abcdefghijklmnopqrstuvwxyz1234567890AB\""}}')"
check_deny "Cloudflare Token 攔截" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Write","tool_input":{"content":"password = \"%(DB_PASSWORD)s\""}}')"
check_allow "Python 格式佔位符放行" "$out"

out="$(run_hook "$SECRET" '{"tool_name":"Write","tool_input":{"content":"password = \"RealSecret12345\"; sample = \"${PLACEHOLDER}\""}}')"
check_deny "同列佔位符不得掩蓋真憑證" "$out"

rm -f "$WORKDIR/.claude/.plan_approved"
out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"lsmalicious"}}')"
check_deny "命令前綴不誤判為唯讀" "$out"

python3 "$APPROVE" >/dev/null
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["approved_at"]=0; json.dump(d,open(p,"w"))' "$WORKDIR/.claude/.plan_approved"
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_deny "過期核准拒絕寫入" "$out" '超過 60 分鐘'

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"rg token . | tee result.txt"}}')"
check_deny "唯讀命令夾帶管線拒絕" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"rm --recursive --force build"}}')"
check_deny "rm 長參數變形仍攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"rm -- -rf"}}')"
check_allow "rm option terminator 後旗標字樣放行" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"rm -- --recursive --force"}}')"
check_allow "rm option terminator 後長旗標字樣放行" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"echo -- $(rm -rf /tmp/example)"}}')"
check_deny "unrelated option terminator 不得隱藏後續 rm" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"echo \"$(rm -rf /tmp/example)\""}}')"
check_deny "雙引號 command substitution rm 仍攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"echo '\''$(rm -rf /tmp/example)'\''"}}')"
check_allow "單引號 command substitution 文字放行" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git reset -- --hard"}}')"
check_allow "git reset option terminator 後旗標字樣放行" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}')"
check_deny "強推參數順序變形仍攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git push origin +main"}}')"
check_deny "leading plus 強推主幹攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git push origin +HEAD:refs/heads/main"}}')"
check_deny "leading plus 完整 refspec 強推主幹攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git -C . push --force-with-lease=main:deadbeef origin HEAD:refs/heads/main"}}')"
check_deny "git 全域參數及帶值 lease 強推主幹攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git -C . push --force main feature"}}')"
check_allow "protected-looking remote 非 protected refspec 放行" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git -C . push --force origin main"}}')"
check_deny "git 全域參數後 protected refspec 強推攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git push origin +HEAD:master"}}')"
check_deny "HEAD refspec 強推 master 攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git push origin +refs/heads/prod"}}')"
check_deny "完整目的 ref 強推 prod 攔截" "$out"

out="$(run_hook "$DANGER" '{"tool_name":"Bash","tool_input":{"command":"git push origin +feature"}}')"
check_allow "leading plus 非保護分支放行" "$out"

# --- 分級模式（核准模式由政策檔設定；此時拆解檔完整、核准旗標已過期） ---

cat > "$WORKDIR/.claude/orchestration-policy.md" <<'EOF'
## 核准模式
- 核准模式：light
EOF
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_allow "light 模式免核准放行" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":".claude/orchestration-policy.md","content":"- 核准模式：light"}}')"
check_deny "禁止工具修改政策檔" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"sed -i .bak s/strict/light/ .claude/orchestration-policy.md"}}')"
check_deny "禁止 Bash 修改政策檔" "$out"

out="$(run_hook "$PLAN" '{"tool_name":"Bash","tool_input":{"command":"cat .claude/orchestration-policy.md"}}')"
check_allow "唯讀讀取政策檔放行" "$out"

rm "$WORKDIR/.claude/plan/decomposition.md"
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_deny "light 模式仍要求拆解" "$out" '找不到拆解文件'

cat > "$WORKDIR/.claude/plan/decomposition.md" <<'EOF'
## 已知資訊
- x
## 缺少的資訊
- y
- 【假設】z
EOF
cat > "$WORKDIR/.claude/orchestration-policy.md" <<'EOF'
- 核准模式：<由人類設定>
EOF
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_deny "模式無法辨識時視為 strict" "$out"

rm -f "$WORKDIR/.claude/.plan_approved"
write_scoped_plan
cat > "$WORKDIR/.claude/orchestration-policy.md" <<'EOF'
- 核准模式：light誤植
EOF
out="$(run_hook "$PLAN" '{"tool_name":"Write","tool_input":{"file_path":"src/a.py","content":"x"}}')"
check_deny "模式尾碼不得部分匹配" "$out" '尚未取得人類核准'

printf '結果：%d 通過，%d 失敗\n' "$pass" "$fail"
test "$fail" -eq 0
