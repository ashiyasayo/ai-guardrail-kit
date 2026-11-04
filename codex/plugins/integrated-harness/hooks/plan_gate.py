#!/usr/bin/env python3
import os
import re
import shlex
import sys
from pathlib import Path
from hook_protocol import deny, load_event, project_root
from approval import is_review_artifact_patch, require_approval

PLAN = ".codex/guardrail/plan/decomposition.md"
POLICY = ".codex/guardrail/orchestration-policy.md"
MARKERS = ("## 已知資訊", "## 缺少的資訊", "【假設】")
MODE = re.compile(r"^\s*-\s+Approval Mode[：:]\s*(strict|standard|light)\s*$", re.MULTILINE)
PATCH_PATH = re.compile(r"^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+)$", re.MULTILINE)
UNSAFE = re.compile(r"[;&|><`\n\r*?\[\]]|\$\(")
READ_ONLY_COMMANDS = {
    "ls", "cat", "head", "tail", "grep", "rg", "pwd", "which",
    "file", "wc", "diff", "stat", "du", "ps", "printenv",
}
READ_ONLY_GIT_SUBCOMMANDS = {"status", "log", "diff", "show", "branch", "rev-parse"}
DISALLOWED_READ_FLAGS = {"--pre", "--hostname-bin", "--ext-diff", "--textconv", "--output"}

def readonly_command(cmd):
    if not isinstance(cmd, str) or UNSAFE.search(cmd): return False
    try: tokens = shlex.split(cmd)
    except ValueError: return False
    if not tokens: return False
    if any(token.split("=", 1)[0] in DISALLOWED_READ_FLAGS for token in tokens[1:]): return False
    if tokens[0] in READ_ONLY_COMMANDS: return True
    if len(tokens) > 1 and tokens[0] == "git" and tokens[1] in READ_ONLY_GIT_SUBCOMMANDS:
        if tokens[1] == "branch":
            return len(tokens) == 2 or all(token in {"--list", "--show-current", "-a", "-r", "-v", "-vv"} for token in tokens[2:])
        return True
    return False

def section(text, heading):
    lines = text.splitlines()
    try: start = lines.index(heading) + 1
    except ValueError: return []
    values = []
    for line in lines[start:]:
        if line.startswith("## "): break
        if line.strip().startswith("- "): values.append(line.strip()[2:].strip().strip("`"))
    return values

def scope_section(text):
    lines = text.splitlines()
    try: start = lines.index("## 允許修改範圍") + 1
    except ValueError: return []
    values = []
    for line in lines[start:]:
        if line.startswith("## "): break
        stripped = line.strip()
        if not stripped.startswith("- "): continue
        item = stripped[2:].strip()
        if item.startswith("`"):
            closing = item.find("`", 1)
            if closing < 0 or "`" in item[closing + 1:]:
                deny("計畫閘門：允許修改範圍的反引號格式無效。")
            item = item[1:closing].strip()
        elif "`" in item:
            deny("計畫閘門：允許修改範圍的反引號格式無效。")
        values.append(item)
    return values

def personal_policy_path():
    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        return Path(codex_home) / "guardrail/orchestration-policy.md"
    # Windows 的 Path.home() 不理會 HOME 環境變數，明確優先採用 HOME 以維持跨平台一致
    home = os.environ.get("HOME")
    return (Path(home) if home else Path.home()) / ".codex/guardrail/orchestration-policy.md"

def resolve_policy_path(root):
    """Project policy wins; an unreadable project policy must not fall back."""
    project_policy = root / POLICY
    if project_policy.exists(): return project_policy
    personal = personal_policy_path()
    if personal.is_file(): return personal
    return project_policy

def policy(root):
    try: text = resolve_policy_path(root).read_text(encoding="utf-8")
    except (OSError, UnicodeError): return "strict", []
    match = MODE.search(text)
    return (match.group(1) if match else "strict"), section(text, "## Strict Bash 測試與建置 Allowlist")

def plan(root):
    try: text = (root / PLAN).read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        deny(
            "計畫閘門：找不到拆解文件。請先用一個獨立的 apply_patch 建立 "
            ".codex/guardrail/plan/decomposition.md；其他 .docs/ 計畫文件不能取代它。"
        )
    if any(marker not in text for marker in MARKERS): deny("計畫閘門：拆解文件缺少必要標記。")
    return text

def scopes(text, root):
    result = []
    for raw in scope_section(text):
        directory = raw.endswith("/")
        candidate = Path(raw)
        if candidate.is_absolute(): deny("計畫閘門：允許範圍必須是專案相對路徑。")
        resolved = (root / candidate).resolve()
        try: resolved.relative_to(root)
        except ValueError: deny("計畫閘門：允許範圍逸出專案。")
        result.append((resolved, directory))
    if not result: deny("計畫閘門：缺少有效允許修改範圍。")
    return result

def in_scope(path, allowed):
    for base, directory in allowed:
        if path == base: return True
        if directory:
            try: path.relative_to(base); return True
            except ValueError: pass
    return False

def patch_targets(data, root):
    patch = data.get("command")
    if not isinstance(patch, str) or not patch.startswith("*** Begin Patch\n") or not patch.rstrip("\r\n").endswith("*** End Patch"):
        deny("Malformed apply_patch command payload.")
    raws = PATCH_PATH.findall(patch)
    if not raws: deny("Malformed apply_patch command payload.")
    targets = []
    for raw in raws:
        item = Path(raw)
        if item.is_absolute(): deny("計畫閘門：目標必須是專案相對路徑。")
        target = (root / item).resolve()
        try: target.relative_to(root)
        except ValueError: deny("計畫閘門：目標逸出專案。")
        targets.append(target)
    return targets

def strict_command(cmd, allowlist, root):
    if not isinstance(cmd, str) or UNSAFE.search(cmd): return False
    try: tokens = shlex.split(cmd)
    except ValueError: return False
    for entry in allowlist:
        try: allowed = shlex.split(entry)
        except ValueError: continue
        if allowed == ["bash", "tests/"]:
            if len(tokens) < 2 or tokens[0] != "bash" or Path(tokens[1]).is_absolute():
                continue
            tests_root = (root / "tests").resolve()
            candidate = (root / tokens[1]).resolve()
            try:
                candidate.relative_to(tests_root)
                return True
            except ValueError:
                continue
        if tokens[:len(allowed)] == allowed:
            return True
    return False

def main():
    event = load_event(sys.stdin); root = project_root(event)
    if os.environ.get("AI_GUARDRAIL_GLOBAL_DEFAULT") == "1" and not (root / PLAN).exists(): return
    tool, data = event["tool_name"], event["tool_input"]
    # 唯讀探索必須能在計畫建立前執行，否則模型無法蒐集撰寫安全範圍所需的事實。
    if tool == "Bash" and readonly_command(data.get("command")): return
    mode, allowlist = policy(root)
    if tool == "apply_patch":
        if is_review_artifact_patch(event, root): return
        targets = patch_targets(data, root)
        plan_path = root / PLAN
        try:
            plan_path.resolve().relative_to(root)
        except ValueError:
            deny("計畫閘門：計畫路徑逸出專案。")
        if plan_path.is_symlink():
            deny("計畫閘門：計畫檔不得是符號連結。")
        # 草稿不代表核准；只修改計畫時可先建立或修訂，後續操作重新驗證內容。
        if targets and all(target == plan_path.resolve() for target in targets):
            return
    text = plan(root)
    # 與 Claude 對齊：light 只要求基本拆解，不解析或強制允許修改範圍。
    allowed = [] if mode == "light" else scopes(text, root)
    if tool == "apply_patch":
        targets = patch_targets(data, root)
        if any(target in {(root / PLAN).resolve(), (root / POLICY).resolve()} for target in targets):
            deny("計畫與政策檔不得由 integrated harness 修改。")
        if mode != "light" and any(not in_scope(target, allowed) for target in targets):
            deny("計畫閘門：目標不在計畫允許修改範圍。")
    elif tool == "Bash":
        cmd = data.get("command")
        if not isinstance(cmd, str): deny("Malformed Bash command payload.")
        if mode == "strict" and not strict_command(cmd, allowlist, root): deny("strict 模式禁止非 allowlist 指令。")
    else:
        deny("Unknown tool is not proven read-only.")
    # standard 保留拆解與範圍；light 只保留基本拆解。兩者皆免人工操作收據。
    if mode in {"standard", "light"}: return
    require_approval(event, root, "integrated-harness")

if __name__ == "__main__": main()
