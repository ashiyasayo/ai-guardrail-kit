#!/usr/bin/env python3
"""
block_pii_prompt.py — 使用者提交提示前的個資阻擋 hook。

事件：UserPromptSubmit

行為：
- 偵測即將送進模型的使用者輸入是否含疑似個資（身分證字號、手機、Email、地址、
  信用卡卡號、學號、護照號碼；規則集中於 pii_patterns.py）
- 命中即整段阻擋（decision="block"），提示使用者自行遮蔽或改用去識別化資料後重新送出
- Claude Code 的 UserPromptSubmit 不支援改寫提示內容（僅 PreToolUse 的
  updatedInput 支援改寫），故本 hook 只能整段阻擋，無法比照
  redact_sensitive_info.py 做「去識別化後放行」；偵測規則沿用同一份定義，
  避免兩層防線各自維護造成漂移

- 未命中時不輸出任何內容，提示照常送進模型

exit code 語意：0（阻擋與否都靠 stdout 的 decision 欄位表達，非 exit code）；
輸入異常時 stderr + exit 2（fail closed）。
"""
import json
import sys
from typing import Optional

sys.dont_write_bytecode = True
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pii_patterns import RULES


def find_pii_kinds(prompt: str) -> list[str]:
    kinds: list[str] = []
    for kind, pattern, _mask, validator in RULES:
        if kind in kinds:
            continue
        # 逐一比對，任一 match 通過驗證函式即算命中（驗證函式為 None 代表命中即算）
        for match in pattern.finditer(prompt):
            if validator is None or validator(match):
                kinds.append(kind)
                break
    return kinds


def check(data: dict) -> Optional[dict]:
    """回傳 UserPromptSubmit 的阻擋輸出物件；None 表示放行。
    供測試與其他工具匯入，不做任何 I/O。"""
    if not isinstance(data, dict):
        return None
    prompt = data.get("prompt", "")
    if not isinstance(prompt, str) or not prompt:
        return None
    kinds = find_pii_kinds(prompt)
    if not kinds:
        return None
    kinds_text = "、".join(kinds)
    return {
        "decision": "block",
        "reason": (
            f"偵測到疑似個資（{kinds_text}），已阻擋本次提交。"
            "請先移除或以去識別化方式（如遮罩、假資料）改寫後再重新送出；"
            "若確有必要處理真實個資，請改用去識別化資料集或另行安全傳輸管道。"
        ),
    }


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("block_pii_prompt: 無法解析 hook 輸入，保守放行。", file=sys.stderr)
        sys.exit(2)
    output = check(data)
    if output is not None:
        print(json.dumps(output, ensure_ascii=False))


if __name__ == "__main__":
    main()

