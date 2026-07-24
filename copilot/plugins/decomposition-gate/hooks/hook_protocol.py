"""VS Code Copilot PreToolUse command hook 的穩定邊界。

欄位與 deny 物件對應實機 spike（VS Code Insiders + Copilot，2026-07-24）擷取到的
payload。護欄模式只依賴本模組的正規化 API，藉此隔離 Preview 契約的變動。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import IO, Any, Dict, NoReturn

# 依 spike 擷取到的 VS Code payload；與 Codex 必填集不同（無 model/permission_mode/turn_id）
_REQUIRED_FIELDS = (
    "cwd",
    "hook_event_name",
    "session_id",
    "tool_input",
    "tool_name",
    "tool_use_id",
    "transcript_path",
)
_REQUIRED_NONEMPTY_STRINGS = ("cwd", "session_id", "tool_name", "tool_use_id")


def _emit(decision: str, reason: str) -> NoReturn:
    """輸出 PreToolUse 決策並以 exit 0 結束。

    出站鐵律：ASCII-safe JSON（ensure_ascii=True）寫入 sys.stdout.buffer，
    繞過 Windows cp950 locale。任何非 JSON 污染都會讓 VS Code 判為 non-JSON
    而 fail-open（等同沒擋），故此處只輸出純 ASCII 的 JSON。
    """
    result = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }
    sys.stdout.buffer.write(json.dumps(result).encode("ascii"))
    raise SystemExit(0)


def deny(reason: str) -> NoReturn:
    """輸出 deny 決策（hook 執行成功、決策為 deny，故 exit 0）。"""
    _emit("deny", reason)


def ask(reason: str) -> NoReturn:
    """請求 VS Code 的原生人工逐次核准。"""
    _emit("ask", reason)


def load_event(stdin: IO[bytes]) -> Dict[str, Any]:
    """讀原始位元組、以 UTF-8 解碼、最小驗證；任何異常一律 fail-closed（deny）。"""
    try:
        event = json.loads(stdin.read().decode("utf-8"))
    except (OSError, UnicodeError, ValueError, RecursionError, TypeError):
        deny("Invalid Copilot hook input")

    if not isinstance(event, dict):
        deny("Invalid Copilot hook input")
    if any(field not in event for field in _REQUIRED_FIELDS):
        deny("Invalid Copilot hook input")
    if event.get("hook_event_name") != "PreToolUse":
        deny("Invalid Copilot hook input")
    if any(
        not isinstance(event.get(field), str) or not event[field]
        for field in _REQUIRED_NONEMPTY_STRINGS
    ):
        deny("Invalid Copilot hook input")
    if not isinstance(event.get("tool_input"), dict):
        deny("Invalid Copilot hook input")
    return event


def project_root(event: Dict[str, Any]) -> Path:
    """回傳存在的工作區根目錄（來自事件 cwd），否則 fail-closed。"""
    cwd = event.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        deny("Invalid Copilot project root")
    try:
        root = Path(cwd).resolve(strict=True)
    except (OSError, RuntimeError):
        deny("Invalid Copilot project root")
    if not root.is_dir():
        deny("Invalid Copilot project root")
    return root
