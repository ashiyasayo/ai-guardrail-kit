"""Protocol-independent dangerous-command and secret checks."""

from __future__ import annotations

import re
import shlex
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
BASH_PARAMETER_FALLBACK_PATTERN = re.compile(
    r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|connection[_-]?string)\b"
    r"\s*=\s*\"?\$\{[A-Za-z_][A-Za-z0-9_]*:[-=]([^}]*)}"
)
BASH_UNQUOTED_ASSIGNMENT_PATTERN = re.compile(
    r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|connection[_-]?string)\b"
    r"\s*=\s*(?!['\"])([^\s;&|]{8,})"
)
SHELL_OPERATORS = {";", "&&", "||", "|", "&"}
PROTECTED_BRANCHES = {"main", "master", "prod", "production", "trunk", "release"}
COMMAND_SUBSTITUTION_PATTERN = re.compile(r"\$\(([^()]*)\)|`([^`]*)`")
REFERENCE_VALUE_PREFIXES = (
    "os.environ", "process.env", "getenv", "system.getenv",
    "environment.", "config.", "env.", "settings.", "vault.",
)


def _command_name(token: str) -> str:
    return token.rsplit("/", 1)[-1]


def _tokenized_commands(command: str):
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return None
    segments, operators, current = [], [], []
    for token in tokens:
        if token in SHELL_OPERATORS:
            if current:
                segments.append(current); current = []; operators.append(token)
            continue
        current.append(token)
    if current:
        segments.append(current)
    return segments, operators[:max(0, len(segments) - 1)]


def _rm_recursive_force(args) -> bool:
    flags = "".join(token[1:] for token in args if token.startswith("-") and not token.startswith("--"))
    long_flags = set(token for token in args if token.startswith("--"))
    return ("r" in flags or "R" in flags or "--recursive" in long_flags) and ("f" in flags or "--force" in long_flags)


def _protected_push(args) -> bool:
    positional = [arg for arg in args if not arg.startswith("-")]
    for refspec in positional[1:]:
        destination = (refspec[1:] if refspec.startswith("+") else refspec).rsplit(":", 1)[-1]
        if destination.removeprefix("refs/heads/") in PROTECTED_BRANCHES:
            return True
    return False


def _token_dangerous(tokens) -> Optional[str]:
    if not tokens:
        return None
    name, args = _command_name(tokens[0]), tokens[1:]
    if name == "sudo" and len(tokens) > 1 and _command_name(tokens[1]) == "rm":
        return "sudo 刪除"
    if name == "rm" and _rm_recursive_force(args):
        return "遞迴強制刪除"
    if name == "git":
        sub = next((arg for arg in args if not arg.startswith("-")), "")
        if sub == "reset" and "--hard" in args: return "硬重置"
        if sub == "filter-branch" or (sub == "push" and "--mirror" in args): return "清空 git 歷史"
        if sub == "push" and any(arg in {"-f", "--force", "--force-with-lease"} for arg in args) and _protected_push(args):
            return "強制推送主幹"
    if name in {"shutdown", "reboot", "poweroff"} or (name == "init" and any(arg in {"0", "6"} for arg in args)): return "關機/重啟"
    if name == "chmod" and "777" in args: return "全開權限"
    if name.startswith("mkfs.") or (name == "dd" and any(arg.startswith("of=/dev/") for arg in args)): return "格式化/覆寫磁碟"
    if name in {"iptables", "pfctl"} and any(arg in {"-F", "--flush"} for arg in args): return "清空防火牆規則"
    if name == "nft" and args[:2] == ["flush", "ruleset"]: return "清空防火牆規則"
    if name == "systemctl" and len(args) >= 2 and args[0] in {"stop", "disable"} and args[1].lower() in {"falcon-sensor", "crowdstrike", "auditd", "firewalld"}: return "停用安全服務"
    if name in {"cat", "less", "more", "head", "tail"} and any(arg in {"/etc/shadow", "/etc/passwd"} for arg in args): return "讀取系統帳密檔"
    if name == "find" and any(arg in {"-exec", "-execdir", "-delete", "-fprintf", "-fprint", "-fls"} for arg in args): return "find 間接寫入"
    return None


def _nested_danger(command: str) -> Optional[str]:
    """檢查命令替換中的巢狀命令。"""
    for match in COMMAND_SUBSTITUTION_PATTERN.finditer(command):
        result = dangerous_command(match.group(1) or match.group(2))
        if result:
            return result
    return None


def _pipeline_danger(segments, operators) -> Optional[str]:
    """檢查下載器直接管線到直譯器的組合。"""
    for index, operator in enumerate(operators):
        if operator != "|" or index + 1 >= len(segments):
            continue
        left, right = segments[index], segments[index + 1]
        if not left or not right or _command_name(left[0]) not in {"curl", "wget"}:
            continue
        right_index = 1 if _command_name(right[0]) == "sudo" and len(right) > 1 else 0
        if _command_name(right[right_index]) in {"bash", "sh", "python", "python3"}:
            return "下載即執行"
    return None


def _parsed_danger(command: str) -> Optional[str]:
    parsed = _tokenized_commands(command)
    if not parsed:
        return None
    segments, operators = parsed
    for segment in segments:
        result = _token_dangerous(segment)
        if result:
            return result
    return _pipeline_danger(segments, operators)


def _regex_danger(command: str) -> Optional[str]:
    """保留 regex fallback，涵蓋無法安全 token 化的既有輸入。"""
    for rule_name, pattern in DANGEROUS_PATTERNS:
        if pattern.search(command):
            return rule_name
    return None


def dangerous_command(command: str) -> Optional[str]:
    """Return the first dangerous-command rule name, without command content."""
    if not isinstance(command, str):
        return None
    return _nested_danger(command) or _parsed_danger(command) or _regex_danger(command)


def pending_content(tool_input: Dict[str, Any]) -> str:
    """Collect text a supported tool is about to write or execute."""
    if not isinstance(tool_input, dict):
        return ""
    parts = []
    for key in ("patch", "cmd", "content", "new_string", "new_source", "command"):
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


def _secret_in_line(line: str) -> Optional[str]:
    safe_fallback_spans = []
    for fallback in BASH_PARAMETER_FALLBACK_PATTERN.finditer(line):
        if _looks_like_secret_literal(fallback.group(2)):
            return "一般憑證指派"
        safe_fallback_spans.append(fallback.span())
    for rule_name, pattern in SECRET_PATTERNS:
        hit = pattern.search(line)
        if hit and not PLACEHOLDER_PATTERN.search(hit.group(0)):
            return rule_name
    for hit in UNQUOTED_ASSIGNMENT_PATTERN.finditer(line):
        if _looks_like_secret_literal(hit.group(1)):
            return "未加引號的憑證指派"
    for hit in BASH_UNQUOTED_ASSIGNMENT_PATTERN.finditer(line):
        if any(hit.start() >= start and hit.end() <= end for start, end in safe_fallback_spans):
            continue
        if _looks_like_secret_literal(hit.group(2)):
            return "一般憑證指派"
    return None


def secret_kind(content: str) -> Optional[str]:
    """Return only the first secret rule name, never the matched value."""
    if not isinstance(content, str):
        return None
    return next((kind for line in content.splitlines() if (kind := _secret_in_line(line))), None)
