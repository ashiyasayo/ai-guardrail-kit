#!/usr/bin/env python3
"""
block_dangerous_commands.py — 危險指令攔截 hook（對應 ORCHESTRATOR.md E 章節：必問清單的硬性底線）

事件：PreToolUse
matcher：Bash

行為：
- 攔截毀滅性 Bash 指令：無論計畫是否已核准，這類操作永遠須由人類親自執行
- 與 plan_gate.py 的分工：plan_gate 管「未核准的一般寫入」，
  本腳本管「即使核准也不准模型執行」的紅線操作

exit code 語意：0 = 放行；2 = 攔截（stderr 回饋給模型）
"""
import json
import re
import sys

# 紅線指令樣式（規則名稱, 正規表示式）——命中即攔截，無核准豁免
DANGEROUS_PATTERNS = (
    # 需同時具備遞迴與強制旗標，且兩者可分開或合併、短或長、任意順序：
    # rm -rf / rm -r -f / rm -r --force / rm --recursive -f 皆須命中。
    # 旗標以 \s 開頭、(?=[\s;&|]|$) 結尾錨定為獨立 token，
    # 避免誤中含 -r/-f 字樣的檔名（如 rm -r my-folder）。
    ("遞迴強制刪除", re.compile(
        r"\brm\b"
        r"(?=[^;&|]*\s(?:-[A-Za-z]*r[A-Za-z]*|--recursive)(?=[\s;&|]|$))"
        r"(?=[^;&|]*\s(?:-[A-Za-z]*f[A-Za-z]*|--force)(?=[\s;&|]|$))"
    )),
    ("sudo 刪除", re.compile(r"\bsudo\s+rm\b")),
    ("資料庫毀滅性操作", re.compile(r"(?i)\b(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)\b")),
    ("強制推送主幹", re.compile(r"\bgit\s+push\s+(?=[^;&|]*\b(?:main|master|prod)\b)(?=[^;&|]*(?:--force(?:-with-lease)?|-f)\b)")),
    ("硬重置", re.compile(r"\bgit\s+reset\s+--hard\b")),
    ("清空 git 歷史", re.compile(r"\bgit\s+filter-branch\b|\bgit\s+push\s+.*--mirror\b")),
    ("全開權限", re.compile(r"\bchmod\s+(-R\s+)?777\b")),
    ("格式化/覆寫磁碟", re.compile(r"\b(mkfs\.\w+|dd\s+.*of=/dev/)")),
    ("關機/重啟", re.compile(r"\b(shutdown|reboot|poweroff|init\s+0|init\s+6)\b")),
    ("清空防火牆規則", re.compile(r"\b(iptables\s+(-F|--flush)|nft\s+flush\s+ruleset|pfctl\s+-F)\b")),
    ("停用安全服務", re.compile(r"(?i)\bsystemctl\s+(stop|disable)\s+(falcon-sensor|crowdstrike|auditd|firewalld)\b")),
    ("讀取系統帳密檔", re.compile(r"/etc/(shadow|passwd)\b")),
    ("下載即執行", re.compile(r"\b(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(bash|sh|python3?)\b")),
)


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("block_dangerous_commands: 無法解析 hook 輸入 JSON，保守攔截。", file=sys.stderr)
        sys.exit(2)

    if hook_input.get("tool_name") != "Bash":
        sys.exit(0)

    command = hook_input.get("tool_input", {}).get("command", "")
    if not command:
        sys.exit(0)

    for rule_name, pattern in DANGEROUS_PATTERNS:
        if pattern.search(command):
            print(
                f"危險指令攔截：命中紅線規則「{rule_name}」，已攔截。"
                "此類操作不在模型授權範圍內（即使計畫已核准亦同），"
                "請將該指令與理由回報給人類，由人類評估後親自執行。"
                "涉及生產環境變更時，須先於測試環境驗證。",
                file=sys.stderr,
            )
            sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
