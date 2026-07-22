"""在 Codex thread 開始時注入 integrated-harness 操作提醒。"""

from __future__ import annotations

import json
import os


REMINDER = """【護欄提醒 · integrated-harness】
修改檔案前先建立 .codex/guardrail/plan/decomposition.md，內容須包含：
## 已知資訊、## 缺少的資訊、【假設】、## 允許修改範圍。
strict／standard 模式在確定性檢查通過後使用 Codex 原生核准；light 模式僅可直接套用範圍內的 apply_patch。
危險指令、明文憑證與個資防線不因核准模式而停用。
"""

def find_reasoning_protocol():
    """尋找隨 plugin 發佈的協定文件；找不到時回傳 None。"""
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = []
    plugin_root = os.environ.get("CODEX_PLUGIN_ROOT")
    if plugin_root:
        candidates.append(os.path.join(plugin_root, "reasoning-protocol.md"))
    candidates.append(os.path.join(os.path.dirname(here), "reasoning-protocol.md"))
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    return None


def build_reminder():
    """建立基本提醒，並安全附加受信任的 plugin 協定文件。"""
    protocol_path = find_reasoning_protocol()
    if not protocol_path:
        return REMINDER
    try:
        with open(protocol_path, encoding="utf-8") as handle:
            return REMINDER + "\n---\n" + handle.read()
    except (OSError, UnicodeError):
        return REMINDER


def main() -> None:
    print(json.dumps({"systemMessage": build_reminder()}, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
