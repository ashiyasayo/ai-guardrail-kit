"""Codex hook 協定邊界：以 Bash／command 為標準，集中處理舊工具格式。"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import IO, Any, Dict, NoReturn


_REQUIRED_FIELDS = (
    "cwd",
    "hook_event_name",
    "model",
    "permission_mode",
    "session_id",
    "tool_input",
    "tool_name",
    "tool_use_id",
    "transcript_path",
    "turn_id",
)
_REQUIRED_NONEMPTY_STRINGS = (
    "cwd",
    "model",
    "permission_mode",
    "session_id",
    "tool_name",
    "tool_use_id",
    "turn_id",
)
def deny(reason: str) -> NoReturn:
    """Emit a Codex PreToolUse denial and terminate successfully.

    Command-hook decisions are communicated as JSON on stdout.  Exit zero is
    intentional: the hook ran successfully and its decision is ``deny``.
    """
    result = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    raise SystemExit(0)


def load_event(stdin: IO[str]) -> Dict[str, Any]:
    """Load and minimally validate one Codex PreToolUse event, failing closed."""
    try:
        event = json.load(stdin)
    except (OSError, UnicodeError, RecursionError, TypeError, ValueError):
        deny("Invalid Codex hook input")

    if not isinstance(event, dict):
        deny("Invalid Codex hook input")
    if any(field not in event for field in _REQUIRED_FIELDS):
        deny("Invalid Codex hook input")
    if event.get("hook_event_name") != "PreToolUse":
        deny("Invalid Codex hook input")
    if any(
        not isinstance(event.get(field), str) or not event[field]
        for field in _REQUIRED_NONEMPTY_STRINGS
    ):
        deny("Invalid Codex hook input")
    if not isinstance(event.get("tool_input"), dict):
        deny("Invalid Codex hook input")
    return normalize_event(event)


def normalize_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """拒絕互相矛盾的別名，避免檢查內容與實際執行內容不同。"""
    result = dict(event)
    tool = result.get("tool_name")
    if tool == "exec_command":
        tool = "Bash"
        result["tool_name"] = tool
    if tool not in ("Bash", "apply_patch"):
        return result
    data = result.get("tool_input")
    if not isinstance(data, dict):
        deny("Invalid Codex hook input")
    data = dict(data)
    alias = "cmd" if tool == "Bash" else "patch"
    if "command" in data and alias in data and data["command"] != data[alias]:
        deny("Conflicting Codex hook input aliases")
    if "command" not in data and alias in data:
        data["command"] = data[alias]
    data.pop(alias, None)
    if not isinstance(data.get("command"), str):
        deny("Malformed Codex command payload")
    result["tool_input"] = data
    return result


def project_root(event: Dict[str, Any]) -> Path:
    """Return the existing Codex working root, or fail closed."""
    cwd = event.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        deny("Invalid Codex project root")
    try:
        root = Path(cwd).resolve(strict=True)
    except (OSError, RuntimeError):
        deny("Invalid Codex project root")
    if not root.is_dir():
        deny("Invalid Codex project root")
    managed_root = os.environ.get("AI_GUARDRAIL_PROJECT_ROOT")
    if managed_root:
        try:
            project = Path(managed_root).resolve(strict=True)
            root.relative_to(project)
        except (OSError, RuntimeError, ValueError):
            deny("Invalid Codex project root")
        return project
    return root
