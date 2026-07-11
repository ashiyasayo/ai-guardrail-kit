#!/usr/bin/env python3
import hashlib
import re
import shlex
import sys
from pathlib import Path
from hook_protocol import ask, deny, load_event, project_root

PLAN = ".codex/guardrail/plan/decomposition.md"
POLICY = ".codex/guardrail/orchestration-policy.md"
MARKERS = ("## 已知資訊", "## 缺少的資訊", "【假設】")
MODE = re.compile(r"^\s*-\s+核准模式[：:]\s*(strict|standard|light)\s*$", re.MULTILINE)
PATCH_PATH = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", re.MULTILINE)
UNSAFE = re.compile(r"[;&|><`\n\r*?\[\]]|\$\(")

def section(text, heading):
    lines = text.splitlines()
    try: start = lines.index(heading) + 1
    except ValueError: return []
    values = []
    for line in lines[start:]:
        if line.startswith("## "): break
        if line.strip().startswith("- "): values.append(line.strip()[2:].strip().strip("`"))
    return values

def policy(root):
    try: text = (root / POLICY).read_text()
    except (OSError, UnicodeError): return "strict", []
    match = MODE.search(text)
    return (match.group(1) if match else "strict"), section(text, "## Strict Bash 測試與建置 Allowlist")

def plan(root):
    try: text = (root / PLAN).read_text()
    except (OSError, UnicodeError): deny("計畫閘門：找不到拆解文件。")
    if any(marker not in text for marker in MARKERS): deny("計畫閘門：拆解文件缺少必要標記。")
    return text

def scopes(text, root):
    result = []
    for raw in section(text, "## 允許修改範圍"):
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
    patch = data.get("patch")
    if not isinstance(patch, str) or not patch.startswith("*** Begin Patch\n") or not patch.endswith("*** End Patch"):
        deny("Malformed native apply_patch payload.")
    raws = PATCH_PATH.findall(patch)
    if not raws: deny("Malformed native apply_patch payload.")
    targets = []
    for raw in raws:
        item = Path(raw)
        if item.is_absolute(): deny("計畫閘門：目標必須是專案相對路徑。")
        target = (root / item).resolve()
        try: target.relative_to(root)
        except ValueError: deny("計畫閘門：目標逸出專案。")
        targets.append(target)
    return targets

def strict_command(cmd, allowlist):
    if not isinstance(cmd, str) or UNSAFE.search(cmd): return False
    try: tokens = shlex.split(cmd)
    except ValueError: return False
    for entry in allowlist:
        try: allowed = shlex.split(entry)
        except ValueError: continue
        if tokens[:len(allowed)] == allowed and (allowed != ["bash", "tests/"] or (len(tokens) > 1 and tokens[1].startswith("tests/") and ".." not in Path(tokens[1]).parts)):
            return True
    return False

def main():
    event = load_event(sys.stdin); root = project_root(event)
    tool, data = event["tool_name"], event["tool_input"]
    mode, allowlist = policy(root)
    text = plan(root); allowed = scopes(text, root)
    if tool == "apply_patch":
        targets = patch_targets(data, root)
        if any(target in {(root / PLAN).resolve(), (root / POLICY).resolve()} for target in targets):
            deny("計畫與政策檔不得由 integrated harness 修改。")
        if any(not in_scope(target, allowed) for target in targets): deny("計畫閘門：目標不在計畫允許修改範圍。")
    elif tool == "exec_command":
        cmd = data.get("cmd")
        if not isinstance(cmd, str): deny("Malformed native exec_command payload.")
        if mode == "strict" and not strict_command(cmd, allowlist): deny("strict 模式禁止非 allowlist 指令。")
    else:
        deny("Unknown tool is not proven read-only.")
    if mode == "light": return
    digest = hashlib.sha256((root / PLAN).read_bytes()).hexdigest()
    ask("Integrated harness native approval; current plan SHA-256: " + digest)

if __name__ == "__main__": main()
