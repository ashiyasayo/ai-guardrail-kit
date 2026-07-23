#!/usr/bin/env python3
"""敏感資料 PreToolUse 統一入口：秘密阻擋後執行個資去識別化。"""
import json
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import block_secrets
import redact_sensitive_info


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("sensitive_data_guard: 無法解析 hook 輸入，保守攔截。", file=sys.stderr)
        sys.exit(2)
    reason = block_secrets.check(hook_input)
    if reason is not None:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }}, ensure_ascii=False))
        return
    output = redact_sensitive_info.check(hook_input)
    if output is not None:
        print(json.dumps({"hookSpecificOutput": output}, ensure_ascii=False))


if __name__ == "__main__":
    main()
