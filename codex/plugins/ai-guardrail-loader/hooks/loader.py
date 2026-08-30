#!/usr/bin/env python3
"""穩定的 Codex hook 入口；只 dispatch 已驗證的離線 cache 資料。"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


def _fail_closed(event_bytes: bytes) -> int:
    try:
        event = json.loads(event_bytes.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        event = {}
    event_name = event.get("hook_event_name") if isinstance(event, dict) else None
    if not isinstance(event_name, str):
        event_name = "PreToolUse"
    if event_name == "SessionStart":
        result = {"hookSpecificOutput": {
            "hookEventName": event_name,
            "additionalContext": "AI Guardrail unavailable (E_RUNTIME_MISSING)",
        }}
    else:
        result = {"hookSpecificOutput": {
            "hookEventName": event_name,
            "permissionDecision": "deny",
            "permissionDecisionReason": "AI Guardrail unavailable (E_RUNTIME_MISSING)",
        }}
    sys.stdout.buffer.write((json.dumps(result, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8"))
    return 0


def main() -> int:
    here = Path(__file__).resolve()
    manager_path = here.with_name("manager.py")
    event_bytes = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)
    if not manager_path.is_file() or manager_path.is_symlink():
        return _fail_closed(event_bytes)
    spec = importlib.util.spec_from_file_location("ai_guardrail_runtime_manager", manager_path)
    if spec is None or spec.loader is None:
        return _fail_closed(event_bytes)
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
        return module.dispatch(event_bytes, module.RuntimeStore(module.codex_home()))
    except Exception:
        return _fail_closed(event_bytes)


if __name__ == "__main__":
    raise SystemExit(main())
