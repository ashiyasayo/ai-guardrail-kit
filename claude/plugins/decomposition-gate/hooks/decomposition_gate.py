#!/usr/bin/env python3
"""
PreToolUse hook: Decomposition Gate for the Deep-and-Broad Reasoning Protocol.

封鎖寫入類工具與具寫入意圖的 Bash 指令，
直到「第一階段拆解」產出物存在且包含必要標記。
搭配 CLAUDE.md 的拆解閘門（decomposition gate）流程使用。

設計原則：最小可稽核規則集（minimal auditable rules）。
WRITE_INTENT_PATTERNS 刻意保持精簡，只涵蓋明確的檔案變更指令，
不試圖窮舉所有可能的寫入路徑；未匹配者交回正常權限流程裁決。
"""
import json
import os
import re
import sys

# 拆解產出物的相對路徑（相對於專案根目錄）
GATE_FILE_RELATIVE_PATH = ".claude/plan/decomposition.md"

# 逃生口：此檔案存在時停用關卡（緊急修復用）
GATE_BYPASS_RELATIVE_PATH = ".claude/plan/.gate_disabled"

# 拆解檔案所在目錄（寫入此目錄的操作一律放行，避免雞生蛋問題）
PLAN_DIR_RELATIVE_PATH = ".claude/plan/"

# 拆解檔案中必須出現的標記（對應思考協定第一階段的三項產出）
REQUIRED_MARKERS = [
    "## 已知資訊",
    "## 缺少的資訊",
    "【假設】",
]

# 受關卡管制的檔案編輯工具（讀取類工具一律放行）
GATED_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}

# Bash 寫入意圖偵測：最小可稽核規則集（3 條）。
# 每項為 (規則名稱, 已編譯的 regex)，規則名稱會出現在 deny 訊息中，便於稽核與除錯。
# 比對前會先以 REDIRECT_NOISE_PATTERN 移除無害的重導向（/dev/null、fd 複製），
# 豁免機制只有這一處。
WRITE_INTENT_PATTERNS = [
    ("redirection", re.compile(r">{1,2}")),                        # > 與 >> 重導向寫檔
    ("file-mutation", re.compile(
        r"(?:^|[|;&]\s*)(?:sudo\s+)?(rm|mv|cp|mkdir|touch)\b")),   # 常見檔案變更指令
    ("sed-in-place", re.compile(r"\bsed\b[^|;&]*\s-[a-zA-Z]*i")),  # sed -i 就地修改
    # 會把內容寫入任意檔案的長選項：git/其他工具的 --output=<path>、
    # sed/GNU 工具的 --in-place。這些不含上列短旗標或重導向，需獨立偵測。
    ("write-flag", re.compile(r"(?:^|\s)--(?:output|in-place)(?:[=\s]|$)")),
]

# 無害重導向的正規化：比對前先移除 >/dev/null、2>/dev/null、2>&1 等
REDIRECT_NOISE_PATTERN = re.compile(r"\d?>{1,2}\s*(?:/dev/null|/dev/stderr)|\d?>&\d")


def emit_decision(decision: str, reason: str) -> None:
    """輸出 PreToolUse 專用的 JSON 決策並結束。"""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }, ensure_ascii=False))
    sys.exit(0)


def resolve_project_dir(hook_input: dict) -> str:
    """優先使用 CLAUDE_PROJECT_DIR，退而使用 hook 輸入中的 cwd。"""
    return os.environ.get("CLAUDE_PROJECT_DIR") or hook_input.get("cwd", ".")


def check_gate(project_dir: str) -> tuple[bool, str]:
    """
    檢查關卡是否滿足。
    回傳 (是否放行, 原因說明)。
    """
    bypass_path = os.path.join(project_dir, GATE_BYPASS_RELATIVE_PATH)
    if os.path.isfile(bypass_path):
        return True, "Gate bypass file present"

    gate_path = os.path.join(project_dir, GATE_FILE_RELATIVE_PATH)
    if not os.path.isfile(gate_path):
        return False, (
            f"Plan gate: 找不到拆解產出物 {GATE_FILE_RELATIVE_PATH}。"
            "請先完成思考協定第一階段（拆解），將結果寫入該檔案後再進行修改。"
            "檔案須包含：## 已知資訊、## 缺少的資訊、以及至少一個【假設】標記。"
        )

    try:
        with open(gate_path, "r", encoding="utf-8") as f:
            content = f.read()
    except (OSError, UnicodeDecodeError) as e:
        # 讀取失敗或非 UTF-8 內容一律 fail closed（deny）
        return False, f"Plan gate: 無法讀取拆解檔案（{e}）。"

    missing_markers = [m for m in REQUIRED_MARKERS if m not in content]
    if missing_markers:
        return False, (
            "Plan gate: 拆解產出物不完整，缺少必要標記："
            f"{'、'.join(missing_markers)}。請補齊後再進行修改。"
        )

    return True, "Decomposition artifact verified"


def detect_bash_write_intent(command: str) -> str | None:
    """
    偵測 Bash 指令是否具寫入意圖。
    回傳匹配的規則名稱；無寫入意圖則回傳 None。
    """
    # 針對 plan 目錄的操作一律不算寫入意圖（允許複製範本等操作）
    if PLAN_DIR_RELATIVE_PATH in command.replace("\\", "/"):
        return None

    # 先移除無害的重導向（/dev/null、fd 複製），再進行比對——唯一的豁免機制
    normalized_command = REDIRECT_NOISE_PATTERN.sub(" ", command)

    for rule_name, pattern in WRITE_INTENT_PATTERNS:
        if pattern.search(normalized_command):
            return rule_name
    return None


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        # stdin 格式異常代表 harness 本身有問題，回報非封鎖錯誤即可
        print("Plan gate: hook 輸入解析失敗", file=sys.stderr)
        sys.exit(1)

    tool_name = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})

    if tool_name in GATED_TOOLS:
        # 檔案編輯工具：允許撰寫拆解檔本身，避免雞生蛋問題
        target_path = tool_input.get("file_path", "")
        if target_path and GATE_FILE_RELATIVE_PATH in target_path.replace("\\", "/"):
            emit_decision("allow", "Writing the decomposition artifact itself is permitted.")
        matched_rule = "file-editing-tool"
    elif tool_name == "Bash":
        # Bash：僅在偵測到寫入意圖時受關卡管制，唯讀指令放行
        command = tool_input.get("command", "")
        matched_rule = detect_bash_write_intent(command)
        if matched_rule is None:
            sys.exit(0)
    else:
        # 其他工具直接放行（不做任何決策，走正常權限流程）
        sys.exit(0)

    project_dir = resolve_project_dir(hook_input)
    passed, reason = check_gate(project_dir)

    if passed:
        # 關卡滿足：不強制 allow，交回正常權限流程裁決
        sys.exit(0)

    emit_decision("deny", f"{reason}（觸發規則：{matched_rule}）")


if __name__ == "__main__":
    main()
