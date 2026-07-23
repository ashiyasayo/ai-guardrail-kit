#!/usr/bin/env python3
"""SessionStart hook：開場即主動注入拆解協定與計畫關卡提醒。

支援兩種佈局：
- marketplace plugin：以環境變數 CLAUDE_PLUGIN_ROOT 為根。
- copy-in（.claude/）：依腳本自身位置回推 .claude/ 目錄。
兩種佈局皆為唯讀讀取，不修改任何檔案；找不到協定檔時只送出基本提醒。
"""
import json
import os
import sys

# 五階段思考協定檔名（marketplace 與 copy-in 兩種佈局同名）
PROTOCOL_FILENAME = "reasoning-protocol.md"


def find_reasoning_protocol():
    """回傳 reasoning-protocol.md 的實際路徑；找不到回傳 None。"""
    candidates = []
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if plugin_root:
        candidates.append(os.path.join(plugin_root, PROTOCOL_FILENAME))
    here = os.path.dirname(os.path.abspath(__file__))
    # copy-in 佈局：hooks/ 的上一層即 .claude/，協定檔置於該層
    candidates.append(os.path.join(os.path.dirname(here), PROTOCOL_FILENAME))
    candidates.append(os.path.join(here, PROTOCOL_FILENAME))
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    return None


def build_reminder():
    reminder = (
        "【護欄提醒 · integrated-harness】\n"
        "動手修改任何檔案前，必須先完成任務拆解：\n"
        "1. 依 plan/decomposition.template.md 格式，寫入 .claude/plan/decomposition.md\n"
        "   必含標記：## 已知資訊、## 缺少的資訊、【假設】、## 允許修改範圍\n"
        "   （要改的檔案路徑務必列進『允許修改範圍』，且不得離開專案根目錄）\n"
        "2. strict 模式下，由人類執行 approve_plan.py 核准（綁 SHA-256，60 分鐘有效）；\n"
        "   standard／light 模式免人工核准，但拆解仍為必要。\n"
        "3. 核准後才能寫入允許範圍內的檔案\n"
        "4. 平台可自行決定任務分解、模型選擇與代理調度，但不得繞過人類授權、\n"
        "   外部副作用、敏感資料、成本、驗收與失敗揭露邊界。\n"
    )
    protocol_path = find_reasoning_protocol()
    if protocol_path:
        try:
            with open(protocol_path, encoding="utf-8") as handle:
                reminder += "\n---\n" + handle.read()
        except OSError:
            pass  # 協定檔讀取失敗不影響基本提醒
    return reminder


def main():
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": build_reminder(),
        }
    }, ensure_ascii=False))
    sys.exit(0)


if __name__ == "__main__":
    main()
