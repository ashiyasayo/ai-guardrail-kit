#!/usr/bin/env python3
"""SessionStart hook：注入風險分級思考協定。"""

import json
import os


def find_protocol():
    """尋找 marketplace 或 copy-in 佈局中的主協定。"""
    candidates = []
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if plugin_root:
        candidates.append(os.path.join(plugin_root, "reasoning-protocol.md"))
    here = os.path.dirname(os.path.abspath(__file__))
    candidates.append(os.path.join(os.path.dirname(here), "reasoning-protocol.md"))
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    return None


def build_context():
    """建立安全的基本提醒，並附加可讀取的協定內容。"""
    context = (
        "【護欄提醒 · decomposition-gate】\n"
        "修改檔案前先建立 .claude/plan/decomposition.md，並包含已知資訊、"
        "缺少資訊與【假設】標記。分析、播報、委派與驗證深度依任務風險調整。\n"
    )
    protocol = find_protocol()
    if not protocol:
        return context
    try:
        with open(protocol, encoding="utf-8") as handle:
            return context + "\n---\n" + handle.read()
    except (OSError, UnicodeError):
        return context


def main():
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": build_context(),
        }
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
