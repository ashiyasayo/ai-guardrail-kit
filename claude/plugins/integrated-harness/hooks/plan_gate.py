#!/usr/bin/env python3
"""PreToolUse hook：拆解文件 + 人類限時核准的雙重計畫關卡。"""
import json
import hashlib
import os
import re
import shlex
import sys
import time

PLAN_PATH = ".claude/plan/decomposition.md"
APPROVAL_PATH = ".claude/.plan_approved"
POLICY_PATH = ".claude/orchestration-policy.md"
APPROVAL_TTL_SECONDS = 3600
# 核准模式由人類在政策檔設定：strict＝須人類核准；standard＝依範圍施作；light＝完成拆解即可施作。
# 缺檔、讀取失敗或無法辨識時一律視為 strict（保守預設）。
APPROVAL_MODES = {"strict", "standard", "light"}
APPROVAL_MODE_PATTERN = re.compile(
    r"(?m)^[ \t]*-[ \t]+核准模式[：:][ \t]*(strict|standard|light)[ \t]*$"
)
STRICT_BASH_ALLOWLIST_HEADER = "## Strict Bash 測試與建置 Allowlist"
POLICY_LIST_ITEM_PATTERN = re.compile(r"^[ \t]*-[ \t]+`([^`]+)`[ \t]*$")
ENV_ASSIGNMENT_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
REQUIRED_MARKERS = ("## 已知資訊", "## 缺少的資訊", "【假設】")
SCOPE_HEADER = "## 允許修改範圍"
FILE_TOOL_PATH_KEYS = {
    "Write": "file_path",
    "Edit": "file_path",
    "MultiEdit": "file_path",
    "NotebookEdit": "notebook_path",
}
PRE_PLAN_SAFE_TOOLS = {
    "Read", "Glob", "Grep", "WebFetch", "WebSearch", "AskUserQuestion",
    "EnterPlanMode", "LSP", "TaskGet", "TaskList", "TaskOutput", "CronList",
    "ListMcpResourcesTool", "ReadMcpResourceTool", "ToolSearch", "WaitForMcpServers",
}
READ_ONLY_COMMANDS = {
    "ls", "cat", "head", "tail", "grep", "rg", "pwd", "which",
    "file", "wc", "diff", "stat", "du", "ps", "printenv",
}
READ_ONLY_GIT_SUBCOMMANDS = {"status", "log", "diff", "show", "branch", "rev-parse"}
UNSAFE_SHELL_PATTERN = re.compile(
    r"[;&|><`\n\r*?\[\]]|\$\(|\btee\b|\bxargs\b|-(?:delete|exec|execdir|ok|okdir|fprint|fprintf|fls)\b"
)
DISALLOWED_READ_FLAGS = {"--pre", "--hostname-bin", "--ext-diff", "--textconv", "--output"}


def emit_deny(reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def project_dir(data: dict) -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd", ".")


def normalized_target(tool_input: dict, root: str, path_key: str) -> str:
    path = tool_input.get(path_key, "")
    if not path:
        return ""
    return os.path.normpath(path if os.path.isabs(path) else os.path.join(root, path))


def exact_path(root: str, relative: str) -> str:
    return os.path.normpath(os.path.join(root, relative))


def is_read_only_bash(command: str) -> bool:
    if not command.strip() or UNSAFE_SHELL_PATTERN.search(command):
        return False
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    if not tokens:
        return False
    if any(token.split("=", 1)[0] in DISALLOWED_READ_FLAGS for token in tokens[1:]):
        return False
    if tokens[0] in READ_ONLY_COMMANDS:
        return True
    if tokens[0] != "git" or len(tokens) < 2 or tokens[1] not in READ_ONLY_GIT_SUBCOMMANDS:
        return False
    if tokens[1] == "branch":
        return len(tokens) == 2 or all(token in {"--list", "--show-current", "-a", "-r", "-v", "-vv"} for token in tokens[2:])
    return True


def approval_mode(root: str) -> str:
    try:
        with open(exact_path(root, POLICY_PATH), encoding="utf-8") as handle:
            content = handle.read()
    except (OSError, UnicodeDecodeError):
        # 讀取失敗或非 UTF-8 內容一律 fail closed，退回最嚴格模式
        return "strict"
    match = APPROVAL_MODE_PATTERN.search(content)
    mode = match.group(1) if match else "strict"
    return mode if mode in APPROVAL_MODES else "strict"


def parse_strict_bash_allowlist(root: str) -> tuple[list[list[str]], str]:
    try:
        with open(exact_path(root, POLICY_PATH), encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        return [], f"無法讀取 strict Bash allowlist：{exc}。"
    try:
        start = lines.index(STRICT_BASH_ALLOWLIST_HEADER) + 1
    except ValueError:
        return [], "政策檔缺少 strict Bash 測試與建置 allowlist。"
    prefixes: list[list[str]] = []
    for line in lines[start:]:
        if line.startswith("## "):
            break
        if not line.strip():
            continue
        match = POLICY_LIST_ITEM_PATTERN.fullmatch(line)
        if not match:
            return [], "strict Bash allowlist 必須使用反引號 Markdown 清單。"
        if UNSAFE_SHELL_PATTERN.search(match.group(1)):
            return [], "strict Bash allowlist 不得包含 shell operator 或 redirect。"
        try:
            tokens = shlex.split(match.group(1))
        except ValueError:
            return [], "strict Bash allowlist 包含無法解析的命令。"
        if not tokens or ENV_ASSIGNMENT_PATTERN.match(tokens[0]):
            return [], "strict Bash allowlist 只能列出單一命令前綴。"
        prefixes.append(tokens)
    if not prefixes:
        return [], "strict Bash allowlist 至少需要一個測試或建置命令。"
    return prefixes, ""


def strict_bash_allowed(command: str, root: str, prefixes: list[list[str]]) -> bool:
    if not command.strip() or UNSAFE_SHELL_PATTERN.search(command):
        return False
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    if not tokens or ENV_ASSIGNMENT_PATTERN.match(tokens[0]):
        return False
    for prefix in prefixes:
        if prefix == ["bash", "tests/"]:
            if len(tokens) < 2 or tokens[0] != "bash":
                continue
            tests_root = os.path.realpath(os.path.join(root, "tests"))
            script = tokens[1]
            if os.path.isabs(script):
                continue
            candidate = os.path.realpath(os.path.join(root, script))
            try:
                if os.path.commonpath([tests_root, candidate]) == tests_root:
                    return True
            except ValueError:
                continue
        elif tokens[:len(prefix)] == prefix:
            return True
    return False


def parse_scopes(content: str, root: str) -> tuple[list[tuple[str, bool]], str]:
    lines = content.splitlines()
    try:
        start = lines.index(SCOPE_HEADER) + 1
    except ValueError:
        return [], f"拆解文件缺少必要標記：{SCOPE_HEADER}。"

    scopes: list[tuple[str, bool]] = []
    root_real = os.path.realpath(root)
    for line in lines[start:]:
        if line.startswith("## "):
            break
        stripped = line.strip()
        if not stripped:
            continue
        if not stripped.startswith("- "):
            return [], "允許修改範圍必須使用 Markdown 清單。"
        raw = stripped[2:].strip().strip("`")
        is_directory = raw.endswith("/")
        if not raw or os.path.isabs(raw) or any(char in raw for char in "*?[]"):
            return [], f"無效的允許修改範圍：{raw or '<空白>'}。"
        resolved = os.path.realpath(os.path.join(root_real, raw))
        try:
            inside_root = os.path.commonpath([root_real, resolved]) == root_real
        except ValueError:
            inside_root = False
        if not inside_root:
            return [], f"允許修改範圍不得離開專案：{raw}。"
        scopes.append((resolved, is_directory))
    if not scopes:
        return [], "允許修改範圍至少需要一個路徑。"
    return scopes, ""


def target_in_scope(target: str, scopes: list[tuple[str, bool]]) -> bool:
    for allowed, is_directory in scopes:
        if not is_directory and target == allowed:
            return True
        if is_directory:
            try:
                if os.path.commonpath([allowed, target]) == allowed:
                    return True
            except ValueError:
                continue
    return False


def check_plan(root: str, mode: str) -> tuple[bool, str, list[tuple[str, bool]]]:
    path = exact_path(root, PLAN_PATH)
    try:
        with open(path, encoding="utf-8") as handle:
            content = handle.read()
    except FileNotFoundError:
        return False, f"找不到拆解文件 {PLAN_PATH}。", []
    except (OSError, UnicodeDecodeError) as exc:
        return False, f"無法讀取拆解文件：{exc}。", []
    missing = [marker for marker in REQUIRED_MARKERS if marker not in content]
    if missing:
        return False, f"拆解文件缺少必要標記：{'、'.join(missing)}。", []
    if mode == "light":
        return True, "", []
    scopes, reason = parse_scopes(content, root)
    return not reason, reason, scopes


def plan_digest(path: str) -> str:
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def check_approval(root: str) -> tuple[bool, str]:
    approval = exact_path(root, APPROVAL_PATH)
    plan = exact_path(root, PLAN_PATH)
    if not os.path.isfile(approval):
        return False, "尚未取得人類核准。"
    try:
        with open(approval, encoding="utf-8") as handle:
            record = json.load(handle)
        approved_at = float(record["approved_at"])
        approved_digest = record["plan_sha256"]
        current_digest = plan_digest(plan)
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
        return False, f"無法驗證核准狀態：{exc}。"
    if approved_digest != current_digest:
        return False, "拆解文件與核准版本不一致，必須重新核准。"
    if approved_at > time.time() + 60:
        return False, "核准時間無效。"
    if time.time() - approved_at > APPROVAL_TTL_SECONDS:
        return False, "人類核准已超過 60 分鐘。"
    return True, ""


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("plan_gate: 無法解析 hook 輸入，保守攔截。", file=sys.stderr)
        sys.exit(2)

    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})
    root = project_dir(data)
    approval = os.path.realpath(exact_path(root, APPROVAL_PATH))
    plan = os.path.realpath(exact_path(root, PLAN_PATH))
    policy = os.path.realpath(exact_path(root, POLICY_PATH))

    mode = approval_mode(root)
    target = ""
    if tool == "Bash":
        command = tool_input.get("command", "")
        if ".plan_approved" in command:
            emit_deny("核准旗標只能由人類在自己的終端機操作，模型不得自我核准或撤銷。")
        if is_read_only_bash(command):
            return
        # 管理目錄不得透過 Bash 寫入，避免 glob、別名與路徑變形繞過保護。
        if ".claude" in command:
            emit_deny(".claude 管理檔只能由人類或受管制的檔案工具修改；不得透過 Bash 變更。")
        if mode == "strict":
            prefixes, reason = parse_strict_bash_allowlist(root)
            if reason or not strict_bash_allowed(command, root, prefixes):
                detail = reason or "命令不在 strict 測試與建置 allowlist。"
                emit_deny(f"strict 模式禁止一般 Bash：{detail}")
    elif tool in FILE_TOOL_PATH_KEYS:
        path_key = FILE_TOOL_PATH_KEYS[tool]
        normalized = normalized_target(tool_input, root, path_key)
        if not normalized:
            emit_deny(f"計畫閘門：{tool} 缺少目標路徑。")
        target = os.path.realpath(normalized)
        if target == approval:
            emit_deny("核准旗標只能由人類操作。")
        if target == policy:
            emit_deny("編排政策檔只能由人類修改，模型不得變更核准模式或授權門檻。")
        if target == plan:
            return
    elif tool in PRE_PLAN_SAFE_TOOLS:
        return

    passed, reason, scopes = check_plan(root, mode)
    if not passed:
        emit_deny(f"計畫閘門：{reason} 請先完成任務拆解。")
    if target and mode != "light" and not target_in_scope(target, scopes):
        emit_deny("計畫閘門：目標不在計畫允許修改範圍。")
    if mode in {"standard", "light"}:
        return
    passed, reason = check_approval(root)
    if not passed:
        emit_deny(f"計畫閘門：{reason} 請由人類審查計畫後執行 `python3 .claude/hooks/approve_plan.py`。")


if __name__ == "__main__":
    main()
