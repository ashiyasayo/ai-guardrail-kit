#!/usr/bin/env python3
"""
redact_sensitive_info.py — 個資去識別化 hook（對應需求：使用者送出敏感資訊
給 AI 時自動去識別化並提示，而非單純阻擋寫入）。

事件：PreToolUse
matcher：Write|Edit|MultiEdit|NotebookEdit

行為：
- 掃描即將寫入的內容，偵測疑似個資（身分證字號、手機、Email、地址、信用卡卡號、
  學號、護照號碼；規則與驗證邏輯集中於 pii_patterns.py）
- 命中時不阻擋：以遮罩後的內容改寫 tool_input，輸出
  permissionDecision="allow" + updatedInput，讓寫入以去識別化後的內容繼續
- 未命中時不輸出任何內容（沿用 Claude Code 預設放行）
- Bash 不在偵測範圍：改寫指令字串容易破壞語法，風險由 block_secrets 之類的
  阻擋型 hook 涵蓋；此處只處理檔案／筆記類寫入工具

exit code 語意：0 = 一律放行（阻擋型判斷不在本 hook 職責）；
輸入異常時 stderr + exit 2（fail closed，交由 guard.py 的既有慣例處理）。
"""
import json
import os
import re
import sys
from typing import Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pii_patterns import RULES

SINGLE_TEXT_FIELDS = {
    "Write": "content",
    "Edit": "new_string",
    "NotebookEdit": "new_source",
}


def redact(content: str) -> tuple[str, list[str]]:
    """回傳（去識別化後內容, 命中的規則名稱清單，去重保序）。"""
    hit_kinds: list[str] = []
    for kind, pattern, mask, validator in RULES:
        def _sub(match: re.Match, _kind=kind, _mask=mask, _validator=validator) -> str:
            # 驗證函式未通過者原樣返回，不遮罩也不計入命中（如 Luhn 不符的長數字）
            if _validator is not None and not _validator(match):
                return match.group(0)
            if _kind not in hit_kinds:
                hit_kinds.append(_kind)
            return _mask(match)
        content = pattern.sub(_sub, content)
    return content, hit_kinds


def extract_content(tool_name: str, tool_input: dict) -> Optional[str]:
    if tool_name in SINGLE_TEXT_FIELDS:
        value = tool_input.get(SINGLE_TEXT_FIELDS[tool_name])
        return value if isinstance(value, str) else None
    if tool_name == "MultiEdit":
        edits = tool_input.get("edits")
        if isinstance(edits, list) and edits and all(
            isinstance(e, dict) and isinstance(e.get("new_string"), str) for e in edits
        ):
            return "\x00".join(e["new_string"] for e in edits)
    return None


def build_updated_input(tool_name: str, tool_input: dict, redacted_content: str) -> dict:
    updated = dict(tool_input)
    if tool_name in SINGLE_TEXT_FIELDS:
        updated[SINGLE_TEXT_FIELDS[tool_name]] = redacted_content
        return updated
    if tool_name == "MultiEdit":
        parts = redacted_content.split("\x00")
        updated["edits"] = [
            {**edit, "new_string": part}
            for edit, part in zip(tool_input.get("edits", []), parts)
        ]
        return updated
    return updated


def check(data: dict) -> Optional[dict]:
    """回傳 hookSpecificOutput 物件（allow + updatedInput）；None 表示無需改寫。
    供 guard.py 匯入，不做任何 I/O。"""
    if not isinstance(data, dict):
        return None
    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})
    if not isinstance(tool_name, str) or not isinstance(tool_input, dict):
        return None
    content = extract_content(tool_name, tool_input)
    if content is None:
        return None
    redacted_content, hit_kinds = redact(content)
    if not hit_kinds:
        return None
    updated_input = build_updated_input(tool_name, tool_input, redacted_content)
    kinds_text = "、".join(hit_kinds)
    return {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": (
            f"偵測到疑似個資（{kinds_text}），已自動去識別化後放行；"
            "請確認遮罩後內容是否仍符合需求，若需保留原始值請改用去識別化資料集或另行安全傳輸。"
        ),
        "updatedInput": updated_input,
    }


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("redact_sensitive_info: 無法解析 hook 輸入，保守放行不改寫。", file=sys.stderr)
        sys.exit(2)
    output = check(data)
    if output is not None:
        print(json.dumps({"hookSpecificOutput": output}, ensure_ascii=False))


if __name__ == "__main__":
    main()

