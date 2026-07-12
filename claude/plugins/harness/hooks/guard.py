#!/usr/bin/env python3
"""
guard.py — PreToolUse 統一進入點：一次啟動直譯器，依序執行三道檢查。

事件：PreToolUse
matcher：Write|Edit|MultiEdit|NotebookEdit|Bash

檢查順序（首個攔截即生效）：
1. block_dangerous_commands — 紅線指令，不因核准而豁免
2. block_secrets — 疑似硬寫憑證
3. plan_gate — 人類核准旗標

exit code 語意：0 = 放行；2 = 攔截（stderr 回饋給模型）
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


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("guard: 無法解析 hook 輸入 JSON，保守攔截。", file=sys.stderr)
        sys.exit(2)

    for module in (block_dangerous_commands, block_secrets, plan_gate):
        reason = module.check(hook_input)
        if reason is not None:
            print(reason, file=sys.stderr)
            sys.exit(2)


if __name__ == "__main__":
    main()
