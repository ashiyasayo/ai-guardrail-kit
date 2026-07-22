#!/usr/bin/env python3
import re
import sys
from hook_protocol import deny, load_event, project_root

PLAN = ".codex/guardrail/plan/decomposition.md"
GATE_BYPASS = ".codex/guardrail/plan/.gate_disabled"
MARKERS = ("## 已知資訊", "## 缺少的資訊", "【假設】")
PATCH_PATH = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", re.MULTILINE)
READ_ONLY = {"list_mcp_resources", "list_mcp_resource_templates", "read_mcp_resource", "view_image"}

def patch_paths(patch):
    if not isinstance(patch, str) or not patch.startswith("*** Begin Patch\n") or not patch.endswith("*** End Patch"):
        return None
    paths = PATCH_PATH.findall(patch)
    return paths or None

def targets_bypass(tool, data):
    """防止模型透過 Codex 工具自建或修改緊急逃生口。"""
    if tool == "apply_patch":
        return any(GATE_BYPASS in path.replace("\\", "/") for path in (patch_paths(data.get("patch")) or []))
    if tool == "exec_command":
        command = data.get("cmd")
        return isinstance(command, str) and GATE_BYPASS in command.replace("\\", "/")
    return False

def main():
    event = load_event(sys.stdin); root = project_root(event)
    tool, data = event["tool_name"], event["tool_input"]
    if targets_bypass(tool, data):
        deny("逃生口 .codex/guardrail/plan/.gate_disabled 只能由人類在自己的終端機建立；模型不得透過工具自建或修改。")
    if (root / GATE_BYPASS).is_file():
        return
    if tool in READ_ONLY:
        return
    if tool == "apply_patch":
        paths = patch_paths(data.get("patch"))
        if paths == [PLAN]:
            plan_path = root / PLAN
            try:
                plan_path.parent.resolve().relative_to(root)
                if plan_path.is_symlink(): deny("Plan gate: decomposition path must not be a symlink.")
            except (OSError, ValueError):
                deny("Plan gate: decomposition path escapes the project.")
            return
        if not paths:
            deny("Plan gate: malformed native apply_patch payload.")
    elif tool == "exec_command":
        # Shell syntax is too broad to prove write-free here; gate it like a write.
        if not isinstance(data.get("cmd"), str):
            deny("Plan gate: malformed native exec_command payload.")
    else:
        deny("Plan gate: unknown tool is not proven read-only.")
    try:
        content = (root / PLAN).read_text()
    except (OSError, UnicodeError):
        deny("Plan gate: 找不到或無法讀取拆解產出物。")
    if any(marker not in content for marker in MARKERS):
        deny("Plan gate: 拆解產出物不完整。")

if __name__ == "__main__":
    main()
