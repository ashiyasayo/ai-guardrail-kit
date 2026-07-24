#!/usr/bin/env sh
# Copilot decomposition-gate 啟動器（POSIX / macOS / Linux）。
#
# 【未於 Copilot 實機驗證】——僅 Windows 主線經 Phase 0 spike 驗證；
# 本檔為附帶支援，行為以 Windows launch.ps1 為對照設計。
#
# POSIX 下 stdin 自然繼承給子程序，無需像 Windows 那樣搬原始位元組。
# 資安鐵律：錯誤時自印 deny JSON（VS Code 對 hook 錯誤預設 fail-open）。
DIR="$(cd "$(dirname "$0")" && pwd)"
PY="${GUARDRAIL_PYTHON:-}"
if [ -z "$PY" ]; then
    if command -v python3 >/dev/null 2>&1; then PY=python3
    elif command -v python >/dev/null 2>&1; then PY=python; fi
fi
DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"decomposition-gate launcher error: %s"}}'
if [ -z "$PY" ]; then
    printf "$DENY" "python not found"
    exit 0
fi
PYTHONUTF8=1 "$PY" "$DIR/decomposition_gate.py"
status=$?
[ "$status" -ne 0 ] && printf "$DENY" "python exit $status"
exit 0
