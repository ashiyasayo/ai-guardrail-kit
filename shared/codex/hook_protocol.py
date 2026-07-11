"""Stable boundary for Codex ``PreToolUse`` command hooks.

The wire fields and denial object match the JSON Schemas embedded in the
installed Codex CLI 0.144.1 binary.  Guardrail modes should depend only on the
small normalized API in this module.
"""

from __future__ import annotations

import json
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
_PERMISSION_MODES = frozenset((
    "default",
    "acceptEdits",
    "plan",
    "bypassPermissions",
    "dontAsk",
))


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
    if event["permission_mode"] not in _PERMISSION_MODES:
        deny("Invalid Codex hook input")
    if not isinstance(event.get("tool_input"), dict):
        deny("Invalid Codex hook input")
    return event


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
    return root
