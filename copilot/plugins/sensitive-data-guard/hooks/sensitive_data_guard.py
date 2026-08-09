#!/usr/bin/env python3
"""PreToolUse hook：Copilot (VS Code) 版敏感資料防線。

依序執行兩道獨立檢查，任一命中即 deny：
1. 明文憑證（block_secrets）
2. 個資（pii_patterns）

與 Claude／Codex 版的兩項刻意差異：

- **個資採 deny，不做遮罩改寫。** Claude／Codex 版輸出 allow + updatedInput 以遮罩後
  內容續行；該機制在 VS Code 上未經實機驗證，若不支援會退化成「allow 未遮罩的原始
  內容」——真實個資照原樣寫入且無錯誤訊息（無聲 fail-open）。deny 沒有這種失敗模式。
- **涵蓋範圍含終端機。** 個資與憑證都掃 run_in_terminal；Claude 版的遮罩刻意排除
  Bash（改寫指令字串會破壞語法），但 deny 沒有這個問題，而 spike 已實測 agent 會用
  終端機繞過檔案寫入的 deny。

掃描對象為遞迴收集的 tool_input 全部字串值，不做欄位名對應（理由見
hook_protocol.collect_strings）。因此不依賴工具名白名單，所有工具都會被掃描。
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import block_secrets
from hook_protocol import collect_strings, deny, load_event
from pii_patterns import find_pii_kinds


def main() -> None:
    event = load_event(sys.stdin.buffer, "PreToolUse")
    content = "\n".join(collect_strings(event["tool_input"]))
    if not content:
        return

    reason = block_secrets.check_content(content)
    if reason is not None:
        deny(reason)

    kinds = find_pii_kinds(content)
    if kinds:
        deny(
            "Personal data blocked: detected "
            f"({', '.join(kinds)}). "
            "This mode blocks instead of masking on Copilot, because VS Code's "
            "input-rewriting contract is unverified and would fail open. "
            "Replace the values with de-identified or synthetic data and retry; "
            "if you must handle real personal data, use a de-identified dataset "
            "or a separate secure channel."
        )

    # 兩道檢查皆未命中：靜默結束，交回 VS Code 正常權限流程裁決（不強制 allow）


if __name__ == "__main__":
    main()
