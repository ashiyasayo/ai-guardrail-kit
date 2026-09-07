#!/usr/bin/env python3
"""
block_dangerous_commands.py — 危險指令攔截 hook（對應 ORCHESTRATOR.md E 章節：必問清單的硬性底線）

事件：PreToolUse
matcher：Bash

行為：
- 攔截毀滅性 Bash 指令：無論計畫是否已核准，這類操作永遠須由人類親自執行
- 與 plan_gate.py 的分工：plan_gate 管「未核准的一般寫入」，
  本腳本管「即使核准也不准模型執行」的紅線操作
- 先以 shlex 正規化命令（消耗 sudo/env/command 等 wrapper 與 git 全域選項），
  再套用規則；無法安全 tokenize 時退回原始字串的 regex 比對
  （AGK-001：git -C .../sudo --.../直譯器 -c 內嵌程式碼等等價繞過形式）

exit code 語意：0 = 放行；2 = 攔截（stderr 回饋給模型）
"""
import json
import re
import shlex
import sys
from typing import List, Optional, Tuple

# 紅線指令樣式（規則名稱, 正規表示式）——命中即攔截，無核准豁免；
# 僅在無法安全 tokenize 時作為 fallback 使用。
DANGEROUS_PATTERNS = (
    # 需同時具備遞迴與強制旗標，且兩者可分開或合併、短或長、任意順序：
    # rm -rf / rm -r -f / rm -r --force / rm --recursive -f 皆須命中。
    # 旗標以 \s 開頭、(?=[\s;&|]|$) 結尾錨定為獨立 token，
    # 避免誤中含 -r/-f 字樣的檔名（如 rm -r my-folder）。
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

SHELL_OPERATORS = {";", "&&", "||", "|", "&"}
PROTECTED_BRANCHES = {"main", "master", "prod", "production", "trunk", "release"}
SUDO_VALUE_FLAGS = {
    "-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U", "-r",
    "--user", "--group", "--host", "--prompt", "--chdir",
    "--close-from", "--role", "--type", "--other-user",
}
GIT_VALUE_FLAGS = {"-C", "-c"}
OPAQUE_INTERPRETERS = {"python", "python3", "perl", "ruby", "node", "php", "pwsh", "powershell"}
OPAQUE_INLINE_FLAGS = {"-c", "-e", "-Command", "-command", "-EncodedCommand", "-encodedcommand"}
SHELL_INTERPRETERS = {"bash", "sh", "zsh", "ksh", "dash"}


def _command_name(token: str) -> str:
    return token.rsplit("/", 1)[-1]


def _tokenized_commands(command: str) -> Optional[Tuple[List[List[str]], List[str]]]:
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return None
    segments: List[List[str]] = []
    operators: List[str] = []
    current: List[str] = []
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
    return segments, operators[:max(0, len(segments) - 1)]


def _strip_command_wrappers(tokens: List[str]) -> List[str]:
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


def _rm_recursive_force(args: List[str]) -> bool:
    flags = "".join(token[1:] for token in args if token.startswith("-") and not token.startswith("--"))
    long_flags = {token for token in args if token.startswith("--")}
    return ("r" in flags or "R" in flags or "--recursive" in long_flags) and ("f" in flags or "--force" in long_flags)


def _git_subcommand(args: List[str]) -> Tuple[str, List[str]]:
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


def _protected_push(sub_args: List[str]) -> bool:
    for refspec in (arg for arg in sub_args if not arg.startswith("-")):
        destination = (refspec[1:] if refspec.startswith("+") else refspec).rsplit(":", 1)[-1]
        if destination.removeprefix("refs/heads/") in PROTECTED_BRANCHES:
            return True
    return False


def _opaque_interpreter_inline_code(name: str, args: List[str]) -> bool:
    return name in OPAQUE_INTERPRETERS and any(arg in OPAQUE_INLINE_FLAGS for arg in args)


def _shell_inline_code(args: List[str]) -> Optional[str]:
    for index, arg in enumerate(args):
        if arg == "-c" and index + 1 < len(args):
            return args[index + 1]
    return None


def _token_dangerous(tokens: List[str]) -> Optional[str]:
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
        if sub == "reset" and "--hard" in sub_args:
            return "硬重置"
        if sub == "filter-branch" or (sub == "push" and "--mirror" in sub_args):
            return "清空 git 歷史"
        if sub == "push" and any(arg in {"-f", "--force", "--force-with-lease"} for arg in sub_args) and _protected_push(sub_args):
            return "強制推送主幹"
    if name in {"shutdown", "reboot", "poweroff"} or (name == "init" and any(arg in {"0", "6"} for arg in args)):
        return "關機/重啟"
    if name == "chmod" and "777" in args:
        return "全開權限"
    if name.startswith("mkfs.") or (name == "dd" and any(arg.startswith("of=/dev/") for arg in args)):
        return "格式化/覆寫磁碟"
    if name in {"iptables", "pfctl"} and any(arg in {"-F", "--flush"} for arg in args):
        return "清空防火牆規則"
    if name == "nft" and args[:2] == ["flush", "ruleset"]:
        return "清空防火牆規則"
    if name == "systemctl" and len(args) >= 2 and args[0] in {"stop", "disable"} and args[1].lower() in {"falcon-sensor", "crowdstrike", "auditd", "firewalld"}:
        return "停用安全服務"
    if name in {"cat", "less", "more", "head", "tail"} and any(arg in {"/etc/shadow", "/etc/passwd"} for arg in args):
        return "讀取系統帳密檔"
    if name in SHELL_INTERPRETERS:
        inline = _shell_inline_code(args)
        if inline is not None:
            nested = _dangerous_command(inline)
            if nested:
                return nested
    elif _opaque_interpreter_inline_code(name, args):
        return "直譯器內嵌程式碼無法靜態驗證安全性"
    return None


def _pipeline_danger(segments: List[List[str]], operators: List[str]) -> Optional[str]:
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


def _regex_danger(command: str) -> Optional[str]:
    for rule_name, pattern in DANGEROUS_PATTERNS:
        if pattern.search(command):
            return rule_name
    return None


def _dangerous_command(command: str) -> Optional[str]:
    parsed = _tokenized_commands(command)
    if parsed is None:
        return _regex_danger(command)
    segments, operators = parsed
    for segment in segments:
        result = _token_dangerous(segment)
        if result:
            return result
    return _pipeline_danger(segments, operators) or _regex_danger(command)


def check(hook_input: dict) -> Optional[str]:
    """回傳攔截原因；None 表示放行。供 guard.py 匯入，不做任何 I/O。"""
    if hook_input.get("tool_name") != "Bash":
        return None

    command = hook_input.get("tool_input", {}).get("command", "")
    if not command:
        return None

    rule_name = _dangerous_command(command)
    if rule_name is not None:
        return (
            f"危險指令攔截：命中紅線規則「{rule_name}」，已攔截。"
            "此類操作不在模型授權範圍內（即使計畫已核准亦同），"
            "請將該指令與理由回報給人類，由人類評估後親自執行。"
            "涉及生產環境變更時，須先於測試環境驗證。"
        )
    return None


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("block_dangerous_commands: 無法解析 hook 輸入 JSON，保守攔截。", file=sys.stderr)
        sys.exit(2)

    reason = check(hook_input)
    if reason is not None:
        print(reason, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
