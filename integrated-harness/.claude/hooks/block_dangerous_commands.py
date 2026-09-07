#!/usr/bin/env python3
"""PreToolUse hook：無論是否核准，一律攔截紅線 Bash 指令。"""
import json
import os
import re
import shlex
import sys
from typing import Optional

SHELL_OPERATORS = {";", "&", "&&", "|", "||"}
PROTECTED_BRANCHES = {"main", "master", "prod"}
RAW_RM_PATTERN = re.compile(
    r"\brm\s+(?:(?:-[A-Za-z]*r[A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*r)\b|"
    r"(?=[^;&|]*--recursive)(?=[^;&|]*--force))"
)
# sudo 選項中會額外消耗下一個 token 的旗標（例如 `sudo -u root rm ...`）。
SUDO_VALUE_FLAGS = {
    "-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U", "-r",
    "--user", "--group", "--host", "--prompt", "--chdir",
    "--close-from", "--role", "--type", "--other-user",
}
# 可執行任意內嵌程式碼、且此處無法可靠靜態解析其語意的直譯器；
# 一旦帶有內嵌程式碼旗標一律保守攔截（無法解析時不視為安全，AGK-001）。
OPAQUE_INTERPRETERS = {"python", "python3", "perl", "ruby", "node", "php", "pwsh", "powershell"}
OPAQUE_INLINE_FLAGS = {"-c", "-e", "-Command", "-command", "-EncodedCommand", "-encodedcommand"}
SHELL_INTERPRETERS = {"bash", "sh", "zsh", "ksh", "dash"}

PATTERNS = (
    ("sudo 刪除", re.compile(r"\bsudo\s+rm\b")),
    ("資料庫毀滅性操作", re.compile(r"(?i)\b(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)\b")),
    ("強制推送主幹", re.compile(r"\bgit\s+push\s+(?=[^;&|]*\b(?:main|master|prod)\b)(?=[^;&|]*(?:--force(?:-with-lease)?|-f)\b)")),
    ("硬重置", re.compile(r"\bgit\s+reset\s+--hard\b")),
    ("清空 Git 歷史", re.compile(r"\bgit\s+filter-branch\b|\bgit\s+push\s+.*--mirror\b")),
    ("全開權限", re.compile(r"\bchmod\s+(-R\s+)?777\b")),
    ("格式化或覆寫磁碟", re.compile(r"\b(mkfs\.\w+|dd\s+.*of=/dev/)")),
    ("關機或重啟", re.compile(r"\b(shutdown|reboot|poweroff|init\s+[06])\b")),
    ("清空防火牆", re.compile(r"\b(iptables\s+(-F|--flush)|nft\s+flush\s+ruleset|pfctl\s+-F)\b")),
    ("停用安全服務", re.compile(
        r"(?i)\bsystemctl\s+(stop|disable)\s+(falcon-sensor|crowdstrike|auditd|firewalld)\b"
    )),
    ("讀取系統帳密檔", re.compile(r"/etc/(shadow|passwd)\b")),
    ("下載即執行", re.compile(r"\b(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(bash|sh|python3?)\b")),
    ("直譯器內嵌程式碼", re.compile(
        r"\b(?:python3?|perl|ruby|node|php|pwsh|powershell)\b[^|;&]*"
        r"\s(?:-c|-e|-Command|-command|-EncodedCommand|-encodedcommand)\s"
    )),
)


def tokenized_commands(command: str) -> Optional[tuple[list[list[str]], list[str]]]:
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return None
    segments: list[list[str]] = []
    operators: list[str] = []
    current: list[str] = []
    for token in tokens:
        if token in SHELL_OPERATORS:
            if current:
                segments.append(current)
                current = []
                operators.append(token)
            continue
        current.append(token)
    if current:
        segments.append(current)
    if len(operators) >= len(segments):
        operators = operators[:max(0, len(segments) - 1)]
    return segments, operators


def command_name(token: str) -> str:
    return os.path.basename(token)


def before_option_terminator(args: list[str]) -> list[str]:
    try:
        return args[:args.index("--")]
    except ValueError:
        return args


def rm_is_recursive_force(args: list[str]) -> bool:
    args = before_option_terminator(args)
    short_flags = "".join(
        token[1:] for token in args if token.startswith("-") and not token.startswith("--")
    )
    long_flags = {token for token in args if token.startswith("--")}
    recursive = "r" in short_flags or "R" in short_flags or "--recursive" in long_flags
    force = "f" in short_flags or "--force" in long_flags
    return recursive and force


def raw_rm_is_recursive_force(command: str) -> bool:
    for segment in re.split(r"[;&|]", command):
        for candidate in re.finditer(r"\brm\s+", segment):
            option_region = re.split(
                r"(?<!\S)--(?=\s|$)", segment[candidate.start():], maxsplit=1
            )[0]
            if RAW_RM_PATTERN.search(option_region):
                return True
    return False


def substitution_rm_is_recursive_force(command: str) -> bool:
    quote = ""
    escaped = False
    index = 0
    while index < len(command) - 1:
        char = command[index]
        if escaped:
            escaped = False
        elif char == "\\" and quote != "'":
            escaped = True
        elif char == "'" and quote != '"':
            quote = "" if quote == "'" else "'"
        elif char == '"' and quote != "'":
            quote = "" if quote == '"' else '"'
        elif char == "$" and command[index + 1] == "(" and quote != "'":
            end = command.find(")", index + 2)
            if end == -1:
                return False
            body = command[index + 2:end]
            try:
                tokens = shlex.split(body, posix=True)
            except ValueError:
                return False
            if tokens and command_name(tokens[0]) == "rm" and rm_is_recursive_force(tokens[1:]):
                return True
            index = end
        index += 1
    return False


def git_subcommand(tokens: list[str]) -> tuple[str, list[str]]:
    index = 1
    options_with_value = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
    while index < len(tokens) and tokens[index].startswith("-"):
        option = tokens[index]
        index += 1
        if option in options_with_value and index < len(tokens):
            index += 1
    if index >= len(tokens):
        return "", []
    return tokens[index], tokens[index + 1:]


def push_is_forced(args: list[str]) -> bool:
    return any(
        arg in {"-f", "--force", "--force-with-lease"}
        or arg.startswith("--force-with-lease=")
        or (arg.startswith("+") and len(arg) > 1)
        for arg in args
    )


def push_targets_protected_branch(args: list[str]) -> bool:
    positional = [arg for arg in args if not arg.startswith("-")]
    for arg in positional[1:]:
        refspec = arg[1:] if arg.startswith("+") else arg
        destination = refspec.rsplit(":", 1)[-1]
        if destination.startswith("refs/heads/"):
            destination = destination[len("refs/heads/"):]
        if destination in PROTECTED_BRANCHES:
            return True
    return False


def strip_sudo_wrapper(tokens: list[str]) -> tuple[bool, list[str]]:
    """消耗 sudo 的旗標與 '--' 選項終止符，回傳（是否曾為 sudo、剩餘 tokens）。

    修正：先前只在 tokens[1] 恰好等於 'rm' 時辨識 sudo，'sudo -- rm'、
    'sudo -u root rm' 等帶旗標或 '--' 的等價形式會被放行（AGK-001）。
    """
    if not tokens or command_name(tokens[0]) != "sudo":
        return False, tokens
    index = 1
    while index < len(tokens) and tokens[index] != "--" and tokens[index].startswith("-"):
        flag = tokens[index]
        index += 1
        if flag in SUDO_VALUE_FLAGS and index < len(tokens) and not tokens[index].startswith("-"):
            index += 1
    if index < len(tokens) and tokens[index] == "--":
        index += 1
    return True, tokens[index:]


def opaque_interpreter_inline_code(name: str, args: list[str]) -> bool:
    return name in OPAQUE_INTERPRETERS and any(arg in OPAQUE_INLINE_FLAGS for arg in args)


def shell_inline_code(args: list[str]) -> Optional[str]:
    for index, arg in enumerate(args):
        if arg == "-c" and index + 1 < len(args):
            return args[index + 1]
    return None


def dangerous_tokens(tokens: list[str]) -> Optional[str]:
    if not tokens:
        return None
    had_sudo, stripped = strip_sudo_wrapper(tokens)
    if not stripped:
        return None
    name = command_name(stripped[0])
    args = stripped[1:]
    if had_sudo and name == "rm":
        return "sudo 刪除"
    if name == "rm" and rm_is_recursive_force(args):
        return "遞迴強制刪除"
    if name == "git":
        subcommand, args = git_subcommand(stripped)
        if subcommand == "reset" and "--hard" in before_option_terminator(args):
            return "硬重置"
        if subcommand == "filter-branch" or (subcommand == "push" and "--mirror" in args):
            return "清空 Git 歷史"
        if subcommand == "push" and push_is_forced(args) and push_targets_protected_branch(args):
            return "強制推送主幹"
    if name in {"shutdown", "reboot", "poweroff"} or (name == "init" and any(arg in {"0", "6"} for arg in args)):
        return "關機或重啟"
    if name == "chmod" and "777" in args:
        return "全開權限"
    if name.startswith("mkfs.") or (name == "dd" and any(arg.startswith("of=/dev/") for arg in args)):
        return "格式化或覆寫磁碟"
    if name == "iptables" and any(arg in {"-F", "--flush"} for arg in args):
        return "清空防火牆"
    if name == "nft" and args[:2] == ["flush", "ruleset"]:
        return "清空防火牆"
    if name == "pfctl" and "-F" in args:
        return "清空防火牆"
    if name == "systemctl" and len(args) >= 2 and args[0] in {"stop", "disable"} and args[1].lower() in {"falcon-sensor", "crowdstrike", "auditd", "firewalld"}:
        return "停用安全服務"
    if name in {"cat", "less", "more", "head", "tail"} and any(arg in {"/etc/shadow", "/etc/passwd"} for arg in args):
        return "讀取系統帳密檔"
    if name in {"mysql", "psql", "sqlcmd"}:
        sql_pattern = PATTERNS[1][1]
        if any(sql_pattern.search(arg) for arg in args):
            return "資料庫毀滅性操作"
    if name in SHELL_INTERPRETERS:
        inline = shell_inline_code(args)
        if inline is not None:
            nested = command_is_dangerous(inline)
            if nested:
                return nested
    elif opaque_interpreter_inline_code(name, args):
        return "直譯器內嵌程式碼無法靜態驗證安全性"
    return None


def dangerous_pipeline(segments: list[list[str]], operators: list[str]) -> Optional[str]:
    interpreters = {"bash", "sh", "python", "python3"}
    for index, operator in enumerate(operators):
        if operator != "|" or index + 1 >= len(segments):
            continue
        left = segments[index]
        right = segments[index + 1]
        if not left or not right:
            continue
        left_name = command_name(left[0])
        right_index = 1 if command_name(right[0]) == "sudo" and len(right) > 1 else 0
        if left_name in {"curl", "wget"} and command_name(right[right_index]) in interpreters:
            return "下載即執行"
    return None


def emit_deny(reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def command_is_dangerous(command: str) -> Optional[str]:
    parsed = tokenized_commands(command)
    if parsed is None:
        if raw_rm_is_recursive_force(command):
            return "遞迴強制刪除"
        for name, pattern in PATTERNS:
            if pattern.search(command):
                return name
        return None
    segments, operators = parsed
    if substitution_rm_is_recursive_force(command):
        return "遞迴強制刪除"
    for segment in segments:
        name = dangerous_tokens(segment)
        if name:
            return name
    return dangerous_pipeline(segments, operators)


def matched_rule(data: dict) -> Optional[str]:
    if data.get("tool_name") != "Bash":
        return None
    command = data.get("tool_input", {}).get("command", "")
    return command_is_dangerous(command)


def check(data: dict) -> Optional[str]:
    """回傳攔截原因；None 表示放行。供 guard.py 匯入，不做任何 I/O。"""
    name = matched_rule(data)
    if name is None:
        return None
    return f"危險指令攔截：命中「{name}」；此規則只涵蓋已知形式，操作仍須遵守平台權限。"


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("block_dangerous_commands: 無法解析 hook 輸入，保守攔截。", file=sys.stderr)
        sys.exit(2)
    reason = check(data)
    if reason is not None:
        emit_deny(reason)


if __name__ == "__main__":
    main()
