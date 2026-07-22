#!/usr/bin/env python3
"""
guard.py — PreToolUse 統一進入點：一次啟動直譯器，依序執行下列檢查。

事件：PreToolUse
matcher：Write|Edit|MultiEdit|NotebookEdit|Bash

檢查順序（首個攔截即生效）：
1. block_dangerous_commands — 紅線指令，不因核准而豁免
2. block_secrets — 疑似硬寫憑證
3. plan_gate — 人類核准旗標
4. redact_sensitive_info — 疑似個資，不阻擋，改寫後放行（見下方 redact 分支）

deny 語意：stdout 輸出 permissionDecision JSON（exit 0）；
輸入異常時 stderr + exit 2（fail closed）。
redact 語意：前三道檢查皆放行後才執行；命中時 stdout 輸出
permissionDecision="allow" + updatedInput（exit 0），不計入 deny 判斷。
"""
import json
import os
import sys

# 不產生 __pycache__，避免污染使用者專案的 .claude 目錄
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import block_dangerous_commands
import block_secrets
import plan_gate
import redact_sensitive_info


def emit_deny(reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("guard: 無法解析 hook 輸入 JSON，保守攔截。", file=sys.stderr)
        sys.exit(2)

    is_scheduled_task = os.environ.get("CLAUDE_SCHEDULED_TASK") == "1"

    for module in (block_dangerous_commands, block_secrets, plan_gate):
        # 排程任務無人類在場核准，故僅豁免 plan_gate；紅線指令與憑證洩漏檢查仍需執行。
        if is_scheduled_task and module is plan_gate:
            continue
        reason = module.check(hook_input)
        if reason is not None:
            emit_deny(reason)

    redact_output = redact_sensitive_info.check(hook_input)
    if redact_output is not None:
        print(json.dumps({"hookSpecificOutput": redact_output}, ensure_ascii=False))


if __name__ == "__main__":
    main()
