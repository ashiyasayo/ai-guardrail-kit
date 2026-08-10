#!/usr/bin/env sh
# Copilot sensitive-data-guard 啟動器（POSIX / macOS / Linux）。
#
# 【未於 Copilot 實機驗證】——僅 Windows 主線經 Phase 0 spike 驗證；
# 本檔為附帶支援，行為以 Windows launch.ps1 為對照設計。
#
# 呼叫形式：sh './.github/hooks/launch.sh' <hook_script.py> <HookEvent>
#
# POSIX 下 stdin 自然繼承給子程序，無需像 Windows 那樣搬原始位元組。
# 資安鐵律：錯誤時自印 deny JSON（VS Code 對 hook 錯誤預設 fail-open）。
DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="${1:-}"
HOOK_EVENT="${2:-PreToolUse}"

# 錯誤輸出用的事件名稱先行淨化：形狀必須與事件相符，對 UserPromptSubmit 輸出
# PreToolUse 形狀很可能被 VS Code 忽略而 fail-open（等同沒擋）。
if [ "$HOOK_EVENT" = "UserPromptSubmit" ]; then
    SAFE_EVENT=UserPromptSubmit
else
    SAFE_EVENT=PreToolUse
fi

# 以 %s 帶入事件名稱與錯誤訊息；printf 的格式字串不得含使用者輸入
DENY_FMT='{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"deny","permissionDecisionReason":"sensitive-data-guard launcher error: %s"}}'

fail() {
    printf "$DENY_FMT" "$SAFE_EVENT" "$1"
    exit 0
}

# 腳本名限制為單純檔名：設定檔若被篡改，不得藉此執行 hooks 目錄外的檔案
case "$HOOK_SCRIPT" in
    '') fail "missing hook script argument" ;;
    */*|*\\*) fail "invalid hook script argument" ;;
    *.py) ;;
    *) fail "invalid hook script argument" ;;
esac
[ -f "$DIR/$HOOK_SCRIPT" ] || fail "hook script not found"

PY="${GUARDRAIL_PYTHON:-}"
if [ -z "$PY" ]; then
    if command -v python3 >/dev/null 2>&1; then PY=python3
    elif command -v python >/dev/null 2>&1; then PY=python; fi
fi
[ -n "$PY" ] || fail "python not found"

PYTHONUTF8=1 "$PY" "$DIR/$HOOK_SCRIPT"
status=$?
[ "$status" -ne 0 ] && fail "python exit $status"
exit 0
