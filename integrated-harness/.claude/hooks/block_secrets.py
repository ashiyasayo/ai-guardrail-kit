#!/usr/bin/env python3
"""PreToolUse hook：攔截寫入內容中的疑似憑證。"""
import json
import re
import sys

PATTERNS = (
    ("AWS Access Key", re.compile(r"AKIA[0-9A-Z]{16}"), None),
    ("私鑰", re.compile(r"-----BEGIN\s+(?:RSA|EC|OPENSSH|DSA|PGP)?\s*PRIVATE KEY-----"), None),
    ("GitHub Token", re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}"), None),
    ("Slack Token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"), None),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"), None),
    ("Cloudflare API Token", re.compile(
        r"(?i)cloudflare[_-]?(?:api[_-]?)?token['\"]?\s*[:=]\s*['\"]([A-Za-z0-9_-]{30,})['\"]"
    ), 1),
    ("一般憑證指派", re.compile(
        r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|connection[_-]?string)\b"
        r"\s*[:=]\s*['\"]([^'\"\s]{8,})['\"]"
    ), 2),
    # 刻意要求 = 前後無空白（連線字串慣例），避免誤中 `password = os.environ[...]`
    ("連線字串密碼", re.compile(r"(?i)\b(?:Password|Pwd)=([^;'\"\s]{6,})(?=[;'\"\s]|$)"), 1),
)
PLACEHOLDER = re.compile(
    r"(?i)(YOUR_[A-Za-z0-9_]*|CHANGE_?ME|PLACEHOLDER|EXAMPLE|<[^>]+>|%\([^)]+\)s|\{\{[^}]+}}|REPLACE_ME|xxx+|\*{3,})"
)
BASH_PARAMETER_FALLBACK_ASSIGNMENT = re.compile(
    r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|connection[_-]?string)\b"
    r"\s*=\s*\"?\$\{[A-Za-z_][A-Za-z0-9_]*:[-=]([^}]*)}"
)
BASH_UNQUOTED_ASSIGNMENT = re.compile(
    r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|connection[_-]?string)\b"
    r"\s*=\s*(?!['\"])([^\s;&|]{8,})"
)
BASH_ENV_REFERENCE = re.compile(r"\$(?:[A-Za-z_][A-Za-z0-9_]*|\{[A-Za-z_][A-Za-z0-9_]*})\Z")

# 未加引號的憑證字面值（.env／YAML／設定檔），涵蓋引號規則與 Bash 專用規則抓不到的
# Write／Edit／NotebookEdit 內容。鍵名可帶底線／連字號前綴（DB_PASSWORD、MY_API_KEY）。
UNQUOTED_ASSIGNMENT = re.compile(
    r"(?i)(?:[A-Za-z0-9]+[_-])*(?:password|passwd|pwd|secret|api[_-]?key|access[_-]?token"
    r"|auth[_-]?token|client[_-]?secret|token)\s*[:=]\s*([^\s'\"`;&|#]{8,})"
)
REFERENCE_VALUE_PREFIXES = (
    "os.environ", "process.env", "getenv", "system.getenv",
    "environment.", "config.", "env.", "settings.", "vault.",
)


def looks_like_secret_literal(value: str) -> bool:
    """判斷未加引號的指派值是否像硬寫憑證字面值（而非變數／函式／佔位符參照）。"""
    if PLACEHOLDER.search(value) or value.startswith("$"):
        return False
    if any(ch in value for ch in "()[]"):
        return False
    if value.lower().startswith(REFERENCE_VALUE_PREFIXES):
        return False
    return any(c.isdigit() for c in value) and any(c.isalpha() for c in value)


class HookInputError(ValueError):
    pass


SINGLE_TEXT_FIELDS = {
    "Write": "content",
    "Edit": "new_string",
    "NotebookEdit": "new_source",
    "Bash": "command",
}


def safe_assignment_value(value: str) -> bool:
    return bool(PLACEHOLDER.fullmatch(value) or BASH_ENV_REFERENCE.fullmatch(value))


def deny(kind: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": f"憑證攔截：偵測到疑似硬編碼的{kind}；請改用環境變數或 Secret Manager。",
    }}, ensure_ascii=False))
    sys.exit(0)


def pending_content(tool_name: str, tool_input: dict) -> str:
    """彙整已知寫入工具與 Bash 可能落盤的文字，不遞迴掃描未知 schema。"""
    if not isinstance(tool_input, dict):
        raise HookInputError("tool_input 必須是物件")
    if tool_name in SINGLE_TEXT_FIELDS:
        key = SINGLE_TEXT_FIELDS[tool_name]
        value = tool_input.get(key)
        if not isinstance(value, str):
            raise HookInputError(f"{tool_name}.{key} 必須是文字")
        return value
    if tool_name == "MultiEdit":
        edits = tool_input.get("edits")
        if not isinstance(edits, list) or not edits:
            raise HookInputError("MultiEdit.edits 必須是非空清單")
        parts: list[str] = []
        for edit in edits:
            if not isinstance(edit, dict) or not isinstance(edit.get("new_string"), str):
                raise HookInputError("MultiEdit.edits[].new_string 必須是文字")
            parts.append(edit["new_string"])
        return "\n".join(parts)
    return ""


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("block_secrets: 無法解析 hook 輸入，保守攔截。", file=sys.stderr)
        sys.exit(2)
    try:
        if not isinstance(data, dict):
            raise HookInputError("hook 輸入必須是物件")
        tool_name = data.get("tool_name", "")
        if not isinstance(tool_name, str):
            raise HookInputError("tool_name 必須是文字")
        content = pending_content(tool_name, data.get("tool_input", {}))
    except HookInputError as exc:
        print(f"block_secrets: 已知工具 schema 不符：{exc}。", file=sys.stderr)
        sys.exit(2)
    for line in content.splitlines():
        safe_fallback_spans: list[tuple[int, int]] = []
        if tool_name == "Bash":
            for fallback in BASH_PARAMETER_FALLBACK_ASSIGNMENT.finditer(line):
                if not safe_assignment_value(fallback.group(2)):
                    deny("一般憑證指派")
                safe_fallback_spans.append(fallback.span())
        for kind, pattern, value_group in PATTERNS:
            for hit in pattern.finditer(line):
                if value_group is not None and any(
                    hit.start(value_group) >= start and hit.end(value_group) <= end
                    for start, end in safe_fallback_spans
                ):
                    continue
                if value_group is None or not safe_assignment_value(hit.group(value_group)):
                    deny(kind)
        if tool_name != "Bash":
            # Bash 已有專用的未加引號規則（含 ${VAR:-default} 處理）；
            # 其餘寫入工具（Write／Edit／MultiEdit／NotebookEdit）在此補上。
            for hit in UNQUOTED_ASSIGNMENT.finditer(line):
                if looks_like_secret_literal(hit.group(1)):
                    deny("未加引號的憑證指派")
        if tool_name == "Bash":
            for hit in BASH_UNQUOTED_ASSIGNMENT.finditer(line):
                if any(
                    hit.start() >= start and hit.end() <= end
                    for start, end in safe_fallback_spans
                ):
                    continue
                if (
                    not safe_assignment_value(hit.group(2))
                ):
                    deny("一般憑證指派")


if __name__ == "__main__":
    main()
