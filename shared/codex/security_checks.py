"""Protocol-independent dangerous-command and secret checks."""

from __future__ import annotations

import re
from typing import Any, Dict, Optional


DANGEROUS_PATTERNS = (
    ("遞迴強制刪除", re.compile(
        r"\brm\b"
        r"(?=[^;&|]*\s(?:-[A-Za-z]*r[A-Za-z]*|--recursive)(?=[\s;&|]|$))"
        r"(?=[^;&|]*\s(?:-[A-Za-z]*f[A-Za-z]*|--force)(?=[\s;&|]|$))"
    )),
    ("sudo 刪除", re.compile(r"\bsudo\s+rm\b")),
    ("資料庫毀滅性操作", re.compile(r"(?i)\b(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)\b")),
    ("強制推送主幹", re.compile(r"\bgit\s+push\s+(?=[^;&|]*\b(?:main|master|prod)\b)(?=[^;&|]*(?:--force(?:-with-lease)?|-f)\b)")),
    ("硬重置", re.compile(r"\bgit\s+reset\s+--hard\b")),
    ("清空 git 歷史", re.compile(r"\bgit\s+filter-branch\b|\bgit\s+push\s+.*--mirror\b")),
    ("全開權限", re.compile(r"\bchmod\s+(-R\s+)?777\b")),
    ("格式化/覆寫磁碟", re.compile(r"\b(mkfs\.\w+|dd\s+.*of=/dev/)")),
    ("關機/重啟", re.compile(r"\b(shutdown|reboot|poweroff|init\s+0|init\s+6)\b")),
    ("清空防火牆規則", re.compile(r"\b(iptables\s+(-F|--flush)|nft\s+flush\s+ruleset|pfctl\s+-F)\b")),
    ("停用安全服務", re.compile(r"(?i)\bsystemctl\s+(stop|disable)\s+(falcon-sensor|crowdstrike|auditd|firewalld)\b")),
    ("讀取系統帳密檔", re.compile(r"/etc/(shadow|passwd)\b")),
    ("下載即執行", re.compile(r"\b(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(bash|sh|python3?)\b")),
)

SECRET_PATTERNS = (
    ("AWS Access Key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("私鑰區塊", re.compile(r"-----BEGIN\s+(RSA|EC|OPENSSH|DSA|PGP)?\s*PRIVATE KEY-----")),
    ("GitHub Token", re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}")),
    ("Slack Token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("Cloudflare API Token", re.compile(r"(?i)cloudflare[_-]?(api[_-]?)?token['\"]?\s*[:=]\s*['\"][A-Za-z0-9_-]{30,}['\"]")),
    ("一般憑證指派", re.compile(r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|connection[_-]?string)\b\s*[:=]\s*['\"][^'\"\s]{8,}['\"]")),
    ("MSSQL/MySQL 連線字串含密碼", re.compile(r"(?i)\b(?:Password|Pwd)=([^;'\"\s]{6,})(?=[;'\"\s]|$)")),
)

PLACEHOLDER_PATTERN = re.compile(
    r"(?i)(YOUR_|CHANGE_?ME|PLACEHOLDER|EXAMPLE|<[^>]+>|\$\{[^}]+\}|%\([^)]+\)s|\{\{[^}]+\}\}|REPLACE_ME|xxx+|\*{3,})"
)
UNQUOTED_ASSIGNMENT_PATTERN = re.compile(
    r"(?i)(?:[A-Za-z0-9]+[_-])*(?:password|passwd|pwd|secret|api[_-]?key|access[_-]?token"
    r"|auth[_-]?token|client[_-]?secret|token)\s*[:=]\s*([^\s'\"`;&|#]{8,})"
)
REFERENCE_VALUE_PREFIXES = (
    "os.environ", "process.env", "getenv", "system.getenv",
    "environment.", "config.", "env.", "settings.", "vault.",
)


def dangerous_command(command: str) -> Optional[str]:
    """Return the first dangerous-command rule name, without command content."""
    if not isinstance(command, str):
        return None
    for rule_name, pattern in DANGEROUS_PATTERNS:
        if pattern.search(command):
            return rule_name
    return None


def pending_content(tool_input: Dict[str, Any]) -> str:
    """Collect text a supported tool is about to write or execute."""
    if not isinstance(tool_input, dict):
        return ""
    parts = []
    for key in ("content", "new_string", "new_source", "command"):
        value = tool_input.get(key)
        if isinstance(value, str):
            parts.append(value)
    edits = tool_input.get("edits", []) or []
    if isinstance(edits, list):
        for edit in edits:
            if isinstance(edit, dict) and isinstance(edit.get("new_string"), str):
                parts.append(edit["new_string"])
    return "\n".join(parts)


def _looks_like_secret_literal(value: str) -> bool:
    if PLACEHOLDER_PATTERN.search(value) or value.startswith("$"):
        return False
    if any(ch in value for ch in "()[]"):
        return False
    if value.lower().startswith(REFERENCE_VALUE_PREFIXES):
        return False
    return any(c.isdigit() for c in value) and any(c.isalpha() for c in value)


def secret_kind(content: str) -> Optional[str]:
    """Return only the first secret rule name, never the matched value."""
    if not isinstance(content, str):
        return None
    for line in content.splitlines():
        for rule_name, pattern in SECRET_PATTERNS:
            hit = pattern.search(line)
            if hit and not PLACEHOLDER_PATTERN.search(hit.group(0)):
                return rule_name
        for hit in UNQUOTED_ASSIGNMENT_PATTERN.finditer(line):
            if _looks_like_secret_literal(hit.group(1)):
                return "未加引號的憑證指派"
    return None
