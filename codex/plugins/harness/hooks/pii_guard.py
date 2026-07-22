"""Codex 的提示個資阻擋與寫入內容去識別化 hook。"""

from __future__ import annotations

import json
import sys
from typing import Any, Dict, List, Optional, Tuple

from pii_patterns import RULES


def redact(text: str) -> Tuple[str, List[str]]:
    kinds: List[str] = []
    for kind, pattern, mask in RULES:
        if pattern.search(text):
            kinds.append(kind)
            text = pattern.sub(mask, text)
    return text, kinds


def prompt_result(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    prompt = event.get("prompt")
    if not isinstance(prompt, str) or not prompt:
        return None
    _, kinds = redact(prompt)
    if not kinds:
        return None
    reason = (
        f"偵測到疑似個資（{'、'.join(kinds)}），已阻擋本次提交。"
        "請先移除或以遮罩、假資料等方式去識別化後再重新送出。"
    )
    return {"continue": False, "stopReason": reason, "systemMessage": reason}


def pre_tool_result(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    updated = dict(tool_input)
    kinds: List[str] = []
    for field in ("patch", "content", "new_string", "new_source"):
        value = tool_input.get(field)
        if not isinstance(value, str):
            continue
        redacted, field_kinds = redact(value)
        if field_kinds:
            updated[field] = redacted
            kinds.extend(kind for kind in field_kinds if kind not in kinds)
    if not kinds:
        return None
    reason = f"偵測到疑似個資（{'、'.join(kinds)}），已自動去識別化後放行。"
    return {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": reason,
        "updatedInput": updated,
    }}


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except (OSError, UnicodeError, RecursionError, TypeError, ValueError):
        print(json.dumps({"continue": False, "stopReason": "Invalid Codex PII hook input"}))
        return
    if not isinstance(event, dict):
        print(json.dumps({"continue": False, "stopReason": "Invalid Codex PII hook input"}))
        return
    result = prompt_result(event) if event.get("hook_event_name") == "UserPromptSubmit" else pre_tool_result(event)
    if result is not None:
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
