#!/usr/bin/env python3
"""PreToolUse hook：Copilot (VS Code) 版 Decomposition Gate。

拆解檔不存在或不完整時，封鎖 VS Code Copilot 的寫入向量：
- create_file / multi_replace_string_in_file（依工具本質封鎖）
- run_in_terminal（整體 gate——shell 語法無法證明無寫入，比照 Codex exec_command；
  spike 已證明對抗性 agent 會用終端機繞過任何「寫入意圖」正則）

唯讀工具與未知工具一律放行（決策 2A）。搭配 .github/hooks 啟動器使用。
"""
import sys

from hook_protocol import deny, load_event, project_root

# 拆解產出物（copilot-native 路徑）
PLAN = ".github/guardrail/plan/decomposition.md"

# 逃生口：此檔案存在時停用關卡（緊急修復用），只能由人類在終端機建立
GATE_BYPASS = ".github/guardrail/plan/.gate_disabled"

# 逃生口檔名（供保護檢查用）：模型不得透過工具自建以自我停用關卡
GATE_BYPASS_BASENAME = ".gate_disabled"

# 拆解檔須含的標記（對應思考協定第一階段三項產出）
MARKERS = ("## 已知資訊", "## 缺少的資訊", "【假設】")

# 受管制的檔案寫入工具（依本質封鎖）
FILE_WRITE_TOOLS = {"create_file", "multi_replace_string_in_file"}

# 終端機工具（整體 gate）
TERMINAL_TOOL = "run_in_terminal"


def target_paths(tool, data):
    """取出工具的目標檔案路徑（供逃生口保護與拆解檔自我豁免）。取不到回空清單。"""
    if tool == "create_file":
        path = data.get("filePath")
        return [path] if isinstance(path, str) else []
    if tool == "multi_replace_string_in_file":
        replacements = data.get("replacements")
        if isinstance(replacements, list):
            return [
                item.get("filePath")
                for item in replacements
                if isinstance(item, dict) and isinstance(item.get("filePath"), str)
            ]
    return []


def targets_bypass(tool, data):
    """偵測工具是否試圖自建或寫入逃生口檔案 .gate_disabled。"""
    if tool in FILE_WRITE_TOOLS:
        return any(
            GATE_BYPASS_BASENAME in path.replace("\\", "/") for path in target_paths(tool, data)
        )
    if tool == TERMINAL_TOOL:
        command = data.get("command")
        return isinstance(command, str) and GATE_BYPASS_BASENAME in command.replace("\\", "/")
    return False


def gate_satisfied(root):
    """拆解檔存在且含全部必要標記時回 True；讀取失敗一律 False（fail-closed）。"""
    try:
        content = (root / PLAN).read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return False
    return all(marker in content for marker in MARKERS)


def main():
    event = load_event(sys.stdin.buffer)
    root = project_root(event)
    tool, data = event["tool_name"], event["tool_input"]

    # 逃生口保護優先於一切關卡判斷：模型不得透過工具自建 .gate_disabled 停用關卡
    if targets_bypass(tool, data):
        deny(
            "逃生口 .github/guardrail/plan/.gate_disabled 只能由人類在終端機建立；"
            "模型不得透過工具自建以停用拆解閘門。"
        )

    # 逃生口存在 → 停用關卡（緊急修復用）
    if (root / GATE_BYPASS).is_file():
        return

    is_file_write = tool in FILE_WRITE_TOOLS
    is_terminal = tool == TERMINAL_TOOL
    if not (is_file_write or is_terminal):
        return  # 唯讀 / 未知工具放行（決策 2A）

    # 撰寫拆解檔本身豁免（避免雞生蛋）——僅檔案寫入工具、且全部目標都指向拆解檔時
    if is_file_write:
        paths = [path.replace("\\", "/") for path in target_paths(tool, data)]
        if paths and all(PLAN in path for path in paths):
            return

    if gate_satisfied(root):
        return  # 關卡通過：不強制 allow，交回 VS Code 正常權限流程裁決

    deny(
        f"Plan gate: 找不到或未完成拆解產出物 {PLAN}。"
        "請先完成思考協定第一階段（拆解），將結果寫入該檔案："
        "須含 ## 已知資訊、## 缺少的資訊、以及至少一個【假設】標記。"
        f"（觸發工具：{tool}）"
    )


if __name__ == "__main__":
    main()
