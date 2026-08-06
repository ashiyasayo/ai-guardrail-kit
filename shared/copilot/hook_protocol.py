"""Generated distribution copy; source: shared/copilot/hook_protocol.py.

VS Code Copilot Agent hooks（Preview）的穩定邊界，涵蓋 PreToolUse 與
UserPromptSubmit 兩個事件。護欄模式只依賴本模組的正規化 API，藉此把 Preview
契約的變動集中在單一位置。

PreToolUse 的欄位與 deny 物件對應實機 spike（VS Code Insiders + Copilot，
2026-07-24）擷取到的 payload。

UserPromptSubmit 的**阻擋輸出形狀未經實機驗證**：spike 只證實輸入端可取得
`prompt`，未記錄「如何輸出才能真的擋下提示」。此處依已驗證的 PreToolUse 慣例
類推（同族 `hookSpecificOutput`），若日後驗證出不同形狀，只需修改
`block_prompt()` 一處。
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import IO, Any, Dict, NoReturn

PRE_TOOL_USE = "PreToolUse"
USER_PROMPT_SUBMIT = "UserPromptSubmit"

# 依 spike 擷取到的 VS Code PreToolUse payload；與 Codex 必填集不同
# （無 model/permission_mode/turn_id）
_PRE_TOOL_USE_FIELDS = (
    "cwd",
    "hook_event_name",
    "session_id",
    "tool_input",
    "tool_name",
    "tool_use_id",
    "transcript_path",
)
_PRE_TOOL_USE_NONEMPTY_STRINGS = ("cwd", "session_id", "tool_name", "tool_use_id")

# UserPromptSubmit 刻意只要求最小欄位集：僅 `prompt` 經 spike 驗證存在。
# 若在此比照 PreToolUse 要求 cwd／session_id／transcript_path，而 VS Code 實際
# 未送其中任一欄位，fail-closed 會變成封鎖使用者的「每一個」提示——包含他用來
# 排除問題的那個提示，形成無法自救的硬鎖死。個資掃描只需要 prompt 本身，
# 不需要檔案系統存取，故不要求 cwd。
_USER_PROMPT_SUBMIT_FIELDS = ("hook_event_name", "prompt")


def _emit(event_name: str, decision: str, reason: str) -> NoReturn:
    """輸出決策並以 exit 0 結束。

    出站鐵律：ASCII-safe JSON（json.dumps 預設 ensure_ascii=True）寫入
    sys.stdout.buffer，繞過 Windows cp950 locale。任何非 JSON 污染都會讓
    VS Code 判為 non-JSON 而 fail-open（等同沒擋），故此處只輸出純 ASCII 的 JSON。
    """
    result = {
        "hookSpecificOutput": {
            "hookEventName": event_name,
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }
    sys.stdout.buffer.write(json.dumps(result).encode("ascii"))
    raise SystemExit(0)


def deny(reason: str) -> NoReturn:
    """PreToolUse 阻擋（hook 執行成功、決策為 deny，故 exit 0）。"""
    _emit(PRE_TOOL_USE, "deny", reason)


def ask(reason: str) -> NoReturn:
    """請求 VS Code 的原生人工逐次核准。"""
    _emit(PRE_TOOL_USE, "ask", reason)


def block_prompt(reason: str) -> NoReturn:
    """UserPromptSubmit 阻擋。

    【未實機驗證】形狀依 PreToolUse 慣例類推；這是本模組唯一需要隨驗證結果
    修正的位置。
    """
    _emit(USER_PROMPT_SUBMIT, "deny", reason)


def _refuse(expected_event: str, reason: str) -> NoReturn:
    """依事件別輸出對應形狀的阻擋。

    形狀必須與事件相符：對 UserPromptSubmit 輸出 PreToolUse 形狀，VS Code 很可能
    直接忽略而 fail-open（等同沒擋）。
    """
    if expected_event == USER_PROMPT_SUBMIT:
        block_prompt(reason)
    deny(reason)


def load_event(
    stdin: IO[bytes], expected_event: str = PRE_TOOL_USE
) -> Dict[str, Any]:
    """讀原始位元組、以 UTF-8 解碼、依事件別做最小驗證。

    任何異常一律 fail-closed（輸出對應事件形狀的阻擋）。`expected_event` 預設為
    PreToolUse 以維持既有呼叫端相容。
    """
    invalid = f"Invalid Copilot hook input ({expected_event})"
    try:
        event = json.loads(stdin.read().decode("utf-8"))
    except (OSError, UnicodeError, ValueError, RecursionError, TypeError):
        _refuse(expected_event, invalid)

    if not isinstance(event, dict):
        _refuse(expected_event, invalid)
    if event.get("hook_event_name") != expected_event:
        _refuse(expected_event, invalid)

    if expected_event == USER_PROMPT_SUBMIT:
        if any(field not in event for field in _USER_PROMPT_SUBMIT_FIELDS):
            _refuse(expected_event, invalid)
        if not isinstance(event.get("prompt"), str):
            _refuse(expected_event, invalid)
        return event

    if any(field not in event for field in _PRE_TOOL_USE_FIELDS):
        _refuse(expected_event, invalid)
    if any(
        not isinstance(event.get(field), str) or not event[field]
        for field in _PRE_TOOL_USE_NONEMPTY_STRINGS
    ):
        _refuse(expected_event, invalid)
    if not isinstance(event.get("tool_input"), dict):
        _refuse(expected_event, invalid)
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


def collect_strings(value: Any) -> list:
    """遞迴收集任意 JSON 結構中的所有字串值（保序）。

    刻意不做欄位名對應：`multi_replace_string_in_file` 承載新內容的欄位名未經
    spike 記錄，若猜錯欄位名，掃描會什麼都看不到而靜默放行——又一個無聲
    fail-open。deny-only 的偵測不需要知道哪個欄位是什麼，只需要知道待寫入的
    文字裡有沒有敏感資料；遞迴走訪同時免疫 Preview 欄位改名。

    代價：filePath、explanation 等欄位一併納入掃描，誤判面較大，屬刻意取捨。
    """
    found = []
    if isinstance(value, str):
        found.append(value)
    elif isinstance(value, dict):
        for item in value.values():
            found.extend(collect_strings(item))
    elif isinstance(value, list):
        for item in value:
            found.extend(collect_strings(item))
    return found
