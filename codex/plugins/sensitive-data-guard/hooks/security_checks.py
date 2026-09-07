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
    ("sudo 刪除", re.compile(r"\bsudo\b(?:\s+(?:-{1,2}\S+))*\s+rm\b")),
    ("資料庫毀滅性操作", re.compile(r"(?i)\b(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)\b")),
    ("強制推送主幹", re.compile(r"\bgit\b(?:\s+-\S+(?:\s+\S+)?)*\s+push\s+(?=[^;&|]*\b(?:main|master|prod)\b)(?=[^;&|]*(?:--force(?:-with-lease)?|-f)\b)")),
    ("硬重置", re.compile(r"\bgit\b(?:\s+-\S+(?:\s+\S+)?)*\s+reset\s+--hard\b")),
    ("清空 git 歷史", re.compile(r"\bgit\b(?:\s+-\S+(?:\s+\S+)?)*\s+filter-branch\b|\bgit\s+push\s+.*--mirror\b")),
    ("全開權限", re.compile(r"\bchmod\s+(-R\s+)?777\b")),
    ("格式化/覆寫磁碟", re.compile(r"\b(mkfs\.\w+|dd\s+.*of=/dev/)")),
    ("關機/重啟", re.compile(r"\b(shutdown|reboot|poweroff|init\s+0|init\s+6)\b")),
    ("清空防火牆規則", re.compile(r"\b(iptables\s+(-F|--flush)|nft\s+flush\s+ruleset|pfctl\s+-F)\b")),
    ("停用安全服務", re.compile(r"(?i)\bsystemctl\s+(stop|disable)\s+(falcon-sensor|crowdstrike|auditd|firewalld)\b")),
    ("讀取系統帳密檔", re.compile(r"/etc/(shadow|passwd)\b")),
    ("下載即執行", re.compile(r"\b(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(bash|sh|python3?)\b")),
    ("直譯器內嵌程式碼", re.compile(
        r"\b(?:python3?|perl|ruby|node|php|pwsh|powershell)\b[^|;&]*"
        r"\s(?:-c|-e|-Command|-command|-EncodedCommand|-encodedcommand)\s"
    )),
)

SECRET_PATTERNS = (
    ("AWS Access Key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("私鑰區塊", re.compile(r"-----BEGIN\s+(RSA|EC|OPENSSH|DSA|PGP)?\s*PRIVATE KEY-----")),
    ("GitHub Token", re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}")),
    ("Slack Token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("Cloudflare API Token", re.compile(r"(?i)cloudflare[_-]?(?:api[_-]?)?token['\"]?\s*[:=]\s*['\"]([A-Za-z0-9_-]{30,})['\"]")),
    ("一般憑證指派", re.compile(r"(?i)\b(?:password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|connection[_-]?string)\b\s*[:=]\s*['\"]([^'\"\s]{8,})['\"]")),
    ("MSSQL/MySQL 連線字串含密碼", re.compile(r"(?i)\b(?:Password|Pwd)=([^;'\"\s]{6,})(?=[;'\"\s]|$)")),
)

PLACEHOLDER_PATTERN = re.compile(
    r"(?i)(?:YOUR_[A-Z0-9_]*|CHANGE_?ME|PLACEHOLDER|EXAMPLE|REPLACE_ME"
    # ${...} 允許一層巢狀（如 bash 的 ${VAR:-${OTHER_VAR}} 參照鏈），
    # 但整個值仍須是單一個平衡的 ${...} 運算式，不得夾帶其他文字。
    r"|<[^<>]+>|\$\{(?:[^{}]|\{[^{}]*\})+\}|%\([^()]+\)s|\{\{[^{}]+\}\}|x{3,}|\*{3,})"
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

# sudo 選項中會額外消耗下一個 token 的旗標（例如 `sudo -u root rm ...`）。
SUDO_VALUE_FLAGS = {
    "-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U", "-r",
    "--user", "--group", "--host", "--prompt", "--chdir",
    "--close-from", "--role", "--type", "--other-user",
}
# git 全域選項中會消耗下一個 token 的旗標（例如 `git -C /tmp/repo reset --hard`）。
GIT_VALUE_FLAGS = {"-C", "-c"}
# 可執行任意內嵌程式碼、且此處無法可靠靜態解析其語意的直譯器；
# 一旦帶有內嵌程式碼旗標一律保守攔截（無法解析時不視為安全）。
OPAQUE_INTERPRETERS = {"python", "python3", "perl", "ruby", "node", "php", "pwsh", "powershell"}
OPAQUE_INLINE_FLAGS = {"-c", "-e", "-Command", "-command", "-EncodedCommand", "-encodedcommand"}
# bash/sh 等可安全遞迴解析的直譯器：直接對 -c 內容遞迴套用相同規則。
SHELL_INTERPRETERS = {"bash", "sh", "zsh", "ksh", "dash"}


def _strip_command_wrappers(tokens):
    """消耗 sudo／env／command 等 wrapper 及其全域選項，回傳實際要執行的 tokens。

    修正：先前只在 tokens[1] 恰好等於 'rm' 時辨識 sudo，'sudo -- rm'、
    'sudo -u root rm' 等帶旗標或 '--' 的等價形式會被放行（AGK-001）。
    """
    tokens = list(tokens)
    changed = True
    while tokens and changed:
        changed = False
        name = _command_name(tokens[0])
        if name == "sudo":
            index = 1
            while index < len(tokens) and tokens[index] != "--" and tokens[index].startswith("-"):
                flag = tokens[index]
                index += 1
                if flag in SUDO_VALUE_FLAGS and index < len(tokens) and not tokens[index].startswith("-"):
                    index += 1
            if index < len(tokens) and tokens[index] == "--":
                index += 1
            tokens = tokens[index:]
            changed = True
        elif name == "env":
            index = 1
            while index < len(tokens) and (tokens[index].startswith("-") or "=" in tokens[index]):
                index += 1
            tokens = tokens[index:]
            changed = True
        elif name == "command":
            index = 1
            while index < len(tokens) and tokens[index].startswith("-"):
                index += 1
            tokens = tokens[index:]
            changed = True
    return tokens


def _git_subcommand(args):
    """回傳 git 全域選項之後的子指令，正確跳過 -C/-c 等會消耗下一個 token 的選項。"""
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in GIT_VALUE_FLAGS:
            index += 2
            continue
        if arg.startswith("-"):
            index += 1
            continue
        return arg, args[index + 1:]
    return "", []


def _opaque_interpreter_inline_code(name, args) -> bool:
    return name in OPAQUE_INTERPRETERS and any(arg in OPAQUE_INLINE_FLAGS for arg in args)


def _shell_inline_code(args):
    for index, arg in enumerate(args):
        if arg == "-c" and index + 1 < len(args):
            return args[index + 1]
    return None


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


def _protected_push(sub_args) -> bool:
    """sub_args 為 git push 子指令之後（不含 'push' 本身）的引數，
    即可能的 <remote> 與 <refspec>… 位置引數。"""
    for refspec in (arg for arg in sub_args if not arg.startswith("-")):
        destination = (refspec[1:] if refspec.startswith("+") else refspec).rsplit(":", 1)[-1]
        if destination.removeprefix("refs/heads/") in PROTECTED_BRANCHES:
            return True
    return False


def _token_dangerous(tokens) -> Optional[str]:
    if not tokens:
        return None
    had_sudo = _command_name(tokens[0]) == "sudo"
    stripped = _strip_command_wrappers(tokens)
    if not stripped:
        return None
    name, args = _command_name(stripped[0]), stripped[1:]
    if had_sudo and name == "rm":
        return "sudo 刪除"
    if name == "rm" and _rm_recursive_force(args):
        return "遞迴強制刪除"
    if name == "git":
        sub, sub_args = _git_subcommand(args)
        if sub == "reset" and "--hard" in sub_args: return "硬重置"
        if sub == "filter-branch" or (sub == "push" and "--mirror" in sub_args): return "清空 git 歷史"
        if sub == "push" and any(arg in {"-f", "--force", "--force-with-lease"} for arg in sub_args) and _protected_push(sub_args):
            return "強制推送主幹"
    if name in {"shutdown", "reboot", "poweroff"} or (name == "init" and any(arg in {"0", "6"} for arg in args)): return "關機/重啟"
    if name == "chmod" and "777" in args: return "全開權限"
    if name.startswith("mkfs.") or (name == "dd" and any(arg.startswith("of=/dev/") for arg in args)): return "格式化/覆寫磁碟"
    if name in {"iptables", "pfctl"} and any(arg in {"-F", "--flush"} for arg in args): return "清空防火牆規則"
    if name == "nft" and args[:2] == ["flush", "ruleset"]: return "清空防火牆規則"
    if name == "systemctl" and len(args) >= 2 and args[0] in {"stop", "disable"} and args[1].lower() in {"falcon-sensor", "crowdstrike", "auditd", "firewalld"}: return "停用安全服務"
    if name in {"cat", "less", "more", "head", "tail"} and any(arg in {"/etc/shadow", "/etc/passwd"} for arg in args): return "讀取系統帳密檔"
    if name == "find" and any(arg in {"-exec", "-execdir", "-delete", "-fprintf", "-fprint", "-fls"} for arg in args): return "find 間接寫入"
    if name in SHELL_INTERPRETERS:
        inline = _shell_inline_code(args)
        if inline is not None:
            nested = dangerous_command(inline)
            if nested:
                return nested
    elif _opaque_interpreter_inline_code(name, args):
        return "直譯器內嵌程式碼無法靜態驗證安全性"
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
    if PLACEHOLDER_PATTERN.fullmatch(value) or value.startswith("$"):
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
        if not hit:
            continue
        # 佔位符判斷只看擷取出的憑證值本身（有擷取群組時），避免任意子字串
        # （如真實密碼後綴 "EXAMPLE"）就整條規則豁免。
        value = hit.group(1) if hit.lastindex else hit.group(0)
        if not PLACEHOLDER_PATTERN.fullmatch(value):
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
