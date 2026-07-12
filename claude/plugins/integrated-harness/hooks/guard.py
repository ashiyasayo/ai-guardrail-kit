#!/usr/bin/env python3
"""
guard.py — PreToolUse 統一進入點：一次啟動直譯器，依序執行三道檢查。

事件：PreToolUse
matcher：*

檢查順序（首個攔截即生效）：
1. block_dangerous_commands — 紅線指令，不因核准而豁免
2. block_secrets — 疑似硬寫憑證
3. plan_gate — 拆解文件 + 人類限時核准

deny 語意：stdout 輸出 permissionDecision JSON（exit 0）；
輸入異常或已知工具 schema 不符時 stderr + exit 2（fail closed）。
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


def emit_deny(reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("guard: 無法解析 hook 輸入，保守攔截。", file=sys.stderr)
        sys.exit(2)

    try:
        for module in (block_dangerous_commands, block_secrets, plan_gate):
            reason = module.check(data)
            if reason is not None:
                emit_deny(reason)
    except block_secrets.HookInputError as exc:
        print(f"guard: 已知工具 schema 不符：{exc}。", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
