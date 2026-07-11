#!/usr/bin/env bash
#
# smoke test: 驗證 decomposition_gate.py 在三種情境下的行為。
# 用法：bash tests/smoke_test.sh
#
set -euo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/hooks/decomposition_gate.py"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/.claude/plan"
export CLAUDE_PROJECT_DIR="$WORKDIR"

pass=0
fail=0

check() {
  local name="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $name"
    echo "    expected to contain: $expected"
    echo "    actual: $actual"
    fail=$((fail + 1))
  fi
}

echo "情境 1：唯讀工具（Read）應直接放行，無 JSON 輸出"
out=$(echo '{"tool_name":"Read","tool_input":{"file_path":"a.py"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "Read 放行（無輸出）" "^$" "${out:-$'\n'}"

echo "情境 2：拆解檔不存在時，Write 應被 deny"
out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "Write 被封鎖" '"permissionDecision": "deny"' "$out"

echo "情境 3：撰寫拆解檔本身應被 allow"
out=$(echo '{"tool_name":"Write","tool_input":{"file_path":".claude/plan/decomposition.md"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "拆解檔寫入放行" '"permissionDecision": "allow"' "$out"

echo "情境 4：拆解檔完整後，Write 應放行（無 JSON 輸出）"
cat > "$WORKDIR/.claude/plan/decomposition.md" <<'EOF'
# 任務拆解
## 已知資訊
- x
## 缺少的資訊
- y
## 假設
- 【假設】z
EOF
out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "關卡通過後放行（無輸出）" "^$" "${out:-$'\n'}"

echo "情境 5：拆解檔缺少標記時，Write 應被 deny"
cat > "$WORKDIR/.claude/plan/decomposition.md" <<'EOF'
# 任務拆解
## 已知資訊
- x
EOF
out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/main.py"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "缺標記被封鎖" '"permissionDecision": "deny"' "$out"

# --- 以下為 Bash 寫入意圖偵測情境（拆解檔仍為不完整狀態） ---

echo "情境 6：唯讀 Bash 指令應放行（grep）"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"grep -r pattern src/"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "唯讀 Bash 放行（無輸出）" "^$" "${out:-$'\n'}"

echo "情境 7：重導向到 /dev/null 應豁免（curl -s url >/dev/null 2>&1）"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"curl -s http://example.com >/dev/null 2>&1"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "/dev/null 豁免放行（無輸出）" "^$" "${out:-$'\n'}"

echo "情境 8：重導向寫檔應被 deny（echo x > file）"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo x > config.txt"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "重導向被封鎖" '"permissionDecision": "deny"' "$out"

echo "情境 9：檔案變更指令應被 deny（rm）"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf build/"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "rm 被封鎖" '"permissionDecision": "deny"' "$out"

echo "情境 10：sed -i 應被 deny"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ src/main.py"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "sed -i 被封鎖" '"permissionDecision": "deny"' "$out"

echo "情境 10a：git --output 寫檔應被 deny（長選項寫入意圖）"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"git diff --output=/tmp/x HEAD~1 HEAD"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "git --output 被封鎖" '"permissionDecision": "deny"' "$out"

echo "情境 10b：sed --in-place 應被 deny（長選項就地修改）"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"sed --in-place s/a/b/ prod.conf"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "sed --in-place 被封鎖" '"permissionDecision": "deny"' "$out"

echo "情境 11：針對 plan 目錄的 Bash 操作應放行（cp 範本）"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"cp .claude/plan/decomposition.template.md .claude/plan/decomposition.md"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "plan 目錄操作放行（無輸出）" "^$" "${out:-$'\n'}"

echo "情境 12：拆解檔完整後，Bash 寫入應放行"
cat > "$WORKDIR/.claude/plan/decomposition.md" <<'EOF'
# 任務拆解
## 已知資訊
- x
## 缺少的資訊
- y
## 假設
- 【假設】z
EOF
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo x > config.txt"},"cwd":"'"$WORKDIR"'"}' | python3 "$HOOK")
check "關卡通過後 Bash 寫入放行（無輸出）" "^$" "${out:-$'\n'}"

echo
echo "結果：$pass 通過，$fail 失敗"
[ "$fail" -eq 0 ]
