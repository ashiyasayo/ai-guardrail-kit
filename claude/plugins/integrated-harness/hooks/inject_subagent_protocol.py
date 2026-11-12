#!/usr/bin/env python3
"""SubagentStart hook：把子代理精簡協定注入剛啟動的子代理。

SessionStart 只作用於主代理，子代理需由官方 SubagentStart 事件注入 context。
僅 marketplace 佈局使用（以 CLAUDE_PLUGIN_ROOT 為根）；copy-in 版由 CLAUDE.md 指向協定，
不註冊此事件，避免重複載入。唯讀、不阻擋：協定檔缺失或讀取失敗時不輸出並正常結束，
不得影響子代理啟動。
"""
import json
import os
import sys

# 子代理精簡協定檔名（與 plugin 根目錄的檔案同名）
PROTOCOL_FILENAME = "reasoning-protocol-subagent.md"


def read_subagent_protocol():
    """回傳協定內容；環境變數未設定、檔案缺失或無法讀取時回傳 None。"""
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if not plugin_root:
        return None
    path = os.path.join(plugin_root, PROTOCOL_FILENAME)
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError):
        return None


def main():
    protocol = read_subagent_protocol()
    if protocol:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "SubagentStart",
                "additionalContext": protocol,
            }
        }, ensure_ascii=False))
    sys.exit(0)


if __name__ == "__main__":
    main()
