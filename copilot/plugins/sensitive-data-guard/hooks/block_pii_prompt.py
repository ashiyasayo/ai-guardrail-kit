#!/usr/bin/env python3
"""UserPromptSubmit hook：Copilot (VS Code) 版提示詞個資阻擋。

命中即整段阻擋，提示使用者自行遮蔽或改用去識別化資料後重新送出。只擋個資、
不擋憑證——與 Claude／Codex 的 sensitive-data-guard 模式邊界一致。

【未實機驗證】阻擋輸出的形狀依已驗證的 PreToolUse 慣例類推（見
hook_protocol.block_prompt）；在實機驗證前，這道防線不可宣稱有效。
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from hook_protocol import block_prompt, load_event
from pii_patterns import find_pii_kinds


def main() -> None:
    event = load_event(sys.stdin.buffer, "UserPromptSubmit")
    kinds = find_pii_kinds(event["prompt"])
    if kinds:
        block_prompt(
            "Personal data blocked: detected "
            f"({', '.join(kinds)}) in your prompt. "
            "Remove the values or replace them with masked or synthetic data, "
            "then resend. If you must handle real personal data, use a "
            "de-identified dataset or a separate secure channel."
        )

    # 未命中：靜默結束，提示照常送進模型


if __name__ == "__main__":
    main()
