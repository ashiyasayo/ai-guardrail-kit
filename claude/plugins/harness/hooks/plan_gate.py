#!/usr/bin/env python3
"""
plan_gate.py — 計畫閘門 hook（對應 ORCHESTRATOR.md H 章節：無例外計畫先行）

事件：PreToolUse
matcher：Write|Edit|MultiEdit|NotebookEdit|Bash

行為：
- 攔截所有寫入性操作（檔案寫入/編輯、具變更性的 Bash 指令），
  除非核准旗標檔存在且在有效期內
- 唯讀 Bash 指令（ls、cat、grep、git status 等）一律放行
- 攔截任何試圖操作旗標檔本身的 Bash 指令（防止模型自我核准）

核准方式（由人類在「自己的終端機」執行，不得透過 Claude 執行）：
    touch .claude/.plan_approved

exit code 語意：0 = 放行；2 = 攔截（stderr 回饋給模型）
"""
import json
import os
import re
import shlex
import sys
import time

# 核准旗標檔的有效期（秒）：預設 60 分鐘，過期即失效，避免一次核准永久有效
APPROVAL_TTL_SECONDS = 3600
APPROVAL_FLAG_RELATIVE_PATH = os.path.join(".claude", ".plan_approved")

# 唯讀 Bash 指令白名單（僅比對指令開頭；含管線或重導向即不視為唯讀）
# 每個項目皆以空白結尾，避免前綴誤判（如 lsmalicious 被當成 ls）；
# 不帶參數的裸指令由 is_read_only_bash 的完全相等比對放行。
READ_ONLY_COMMAND_PREFIXES = (
    "ls ", "cat ", "head ", "tail ", "grep ", "rg ", "find ",
    "pwd ", "echo ", "which ", "file ", "wc ", "diff ", "stat ",
    "git status", "git log", "git diff", "git show", "git branch",
)

# 不安全 shell 結構：命中任一者即不視為唯讀。
# 單一規則同時涵蓋：指令串接（; & | ）、重導向（> <）、
# 指令替換（` 與 $(）、以及可間接執行/刪除/寫檔的參數
# （tee、xargs、find 的 -delete/-exec/-fprintf 家族）。
# 不需逐一列舉寫入指令（mv/rm/npm install 等）——它們不符合白名單開頭，
# 本來就會被攔截；本樣式只負責防止「白名單開頭 + 危險結構」的混入。
UNSAFE_SHELL_PATTERN = re.compile(
    r"([;&|><`]|\$\(|\btee\b|\bxargs\b|-(?:delete|exec|execdir|ok|okdir|fprint|fprintf|fls)\b)"
)

# 旗標檔指涉樣式：直接寫出檔名，或以 glob 迂迴指涉 .claude 下的檔案
# （如 touch .claude/.plan*），兩者一律視為操作核准旗標。
APPROVAL_FLAG_REFERENCE_PATTERN = re.compile(r"\.plan_approved|\.claude/\S*[*?\[]")

# 白名單指令中會把內容寫入任意檔案或執行外部程式的選項：
# git diff/log/show --output=<path> 可寫檔；--ext-diff/--textconv/--pre/
# --hostname-bin 可經 git 設定執行任意命令。命中任一者即不視為唯讀。
DISALLOWED_READ_FLAGS = {"--output", "--ext-diff", "--textconv", "--pre", "--hostname-bin"}


def get_project_dir() -> str:
    """取得專案根目錄：優先使用 CLAUDE_PROJECT_DIR，否則退回目前工作目錄。"""
    return os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())


def is_approval_valid(flag_path: str) -> bool:
    """檢查核准旗標檔是否存在且未過期。"""
    if not os.path.isfile(flag_path):
        return False
    age_seconds = time.time() - os.path.getmtime(flag_path)
    return age_seconds <= APPROVAL_TTL_SECONDS


def is_read_only_bash(command: str) -> bool:
    """判斷 Bash 指令是否為唯讀：符合白名單開頭、不含不安全 shell 結構，
    且不帶會寫檔或執行外部程式的選項（如 git --output=<path>）。"""
    stripped = command.strip()
    if UNSAFE_SHELL_PATTERN.search(stripped):
        return False
    # 逐 token 檢查禁用選項；無法解析（引號不成對等）時保守視為非唯讀
    try:
        tokens = shlex.split(stripped)
    except ValueError:
        return False
    if any(token.split("=", 1)[0] in DISALLOWED_READ_FLAGS for token in tokens[1:]):
        return False
    return any(
        stripped == prefix.strip() or stripped.startswith(prefix)
        for prefix in READ_ONLY_COMMAND_PREFIXES
    )


def touches_approval_flag(command: str) -> bool:
    """偵測 Bash 指令是否試圖操作核准旗標檔（防止模型自我核准或延長 TTL）。"""
    return bool(APPROVAL_FLAG_REFERENCE_PATTERN.search(command))


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # 輸入異常時保守處理：攔截並要求人工確認
        print("plan_gate: 無法解析 hook 輸入 JSON，保守攔截。", file=sys.stderr)
        sys.exit(2)

    tool_name = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})
    flag_path = os.path.join(get_project_dir(), APPROVAL_FLAG_RELATIVE_PATH)

    if tool_name == "Bash":
        command = tool_input.get("command", "")

        # 鐵則一：任何試圖操作旗標檔的指令，無論核准與否一律攔截
        if touches_approval_flag(command):
            print(
                "計畫閘門：偵測到操作核准旗標檔的指令，已攔截。"
                "核准只能由人類在自己的終端機執行，模型不得自我核准。",
                file=sys.stderr,
            )
            sys.exit(2)

        # 唯讀指令放行（H 章節：計畫核准前只有讀取與分析權）
        if is_read_only_bash(command):
            sys.exit(0)
    else:
        # 鐵則一（檔案工具版）：即使核准有效，也不得以 Write/Edit 觸碰旗標檔，
        # 否則模型可藉改寫旗標更新 mtime、無限延長核准時間窗
        target = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        if target:
            target_real = os.path.realpath(os.path.join(get_project_dir(), target))
            if target_real == os.path.realpath(flag_path):
                print(
                    "計畫閘門：核准旗標檔只能由人類在自己的終端機操作，"
                    "模型不得透過檔案工具建立、改寫或延長核准。",
                    file=sys.stderr,
                )
                sys.exit(2)

    # 寫入性操作（Write/Edit/MultiEdit/NotebookEdit 或非唯讀 Bash）：檢查核准
    if is_approval_valid(flag_path):
        sys.exit(0)

    print(
        "計畫閘門：本操作屬寫入性行為，但未偵測到有效的計畫核准。"
        "請先向人類提交執行計畫（任務分解、指派模型、驗收標準、風險點），"
        "由人類在其終端機執行 `touch .claude/.plan_approved` 核准後方可施作。"
        f"核准有效期為 {APPROVAL_TTL_SECONDS // 60} 分鐘。",
        file=sys.stderr,
    )
    sys.exit(2)


if __name__ == "__main__":
    main()
