#!/usr/bin/env bash
set -euo pipefail
# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
export PYTHONUTF8=${PYTHONUTF8:-1}
cd "$(dirname "$0")/.."

# harness 與 integrated-harness 的 block_secrets.py／block_dangerous_commands.py
# 為刻意分歧的同源分支（實作與訊息不同）。本測試以「共同行為語料」把
# 「修一邊要記得看另一邊」的人工紀律變成機器守護：兩邊對同一輸入的
# 攔截／放行判定必須一致。新增繞過修補時，請把攻擊樣本加入下方語料。
python3 - <<'PY'
import importlib.util
import pathlib
import sys

root = pathlib.Path.cwd()


def load(alias: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


harness_secrets = load("h_secrets", root / "harness/.claude/hooks/block_secrets.py")
integrated_secrets = load("i_secrets", root / "integrated-harness/.claude/hooks/block_secrets.py")
sensitive_secrets = load("s_secrets", root / "claude/plugins/sensitive-data-guard/hooks/block_secrets.py")
harness_danger = load("h_danger", root / "harness/.claude/hooks/block_dangerous_commands.py")
integrated_danger = load("i_danger", root / "integrated-harness/.claude/hooks/block_dangerous_commands.py")


def verdict(module, event):
    """回傳 True＝攔截、False＝放行；integrated 版對 schema 不符也視為攔截。"""
    try:
        return module.check(event) is not None
    except Exception:
        return True


# --- 憑證語料：(說明, tool_name, tool_input, 兩邊皆須攔截?) ---
SECRET_CASES = [
    ("AWS Access Key 寫檔", "Write",
     {"file_path": "a.py", "content": "key = 'AKIAABCDEFGHIJKLMNOP'"}, True),
    ("私鑰區塊寫檔", "Write",
     {"file_path": "k.pem", "content": "-----BEGIN RSA PRIVATE KEY-----"}, True),
    ("GitHub Token 寫檔", "Write",
     {"file_path": "a.py", "content": "t = 'ghp_" + "a1" * 20 + "'"}, True),
    ("Slack Token 於 Bash", "Bash",
     {"command": "echo xoxb-1234567890-abcdef"}, True),
    ("JWT 寫檔", "Write",
     {"file_path": "a.txt",
      "content": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdEFGH1234ijkl"}, True),
    ("引號密碼指派", "Write",
     {"file_path": "cfg.py", "content": "password = 'Sup3rS3cretVal'"}, True),
    ("連線字串密碼", "Write",
     {"file_path": "web.config", "content": "Server=db;Password=Re4lSecret;"}, True),
    ("未加引號 .env 憑證", "Write",
     {"file_path": ".env", "content": "DB_PASSWORD=Sup3rS3cretVal"}, True),
    ("佔位符不攔截", "Write",
     {"file_path": ".env.example", "content": "API_KEY=YOUR_API_KEY"}, False),
    ("環境變數參照不攔截", "Write",
     {"file_path": "cfg.py", "content": "password = os.environ['DB_PASSWORD']"}, False),
    ("一般程式碼不攔截", "Write",
     {"file_path": "a.py", "content": "def add(a, b):\n    return a + b\n"}, False),
]

# --- 危險指令語料：(說明, command, 兩邊皆須攔截?) ---
DANGER_CASES = [
    ("遞迴強制刪除", "rm -rf /tmp/x", True),
    ("旗標分開的遞迴強制刪除", "rm -r -f build", True),
    ("清空 Git 歷史", "git filter-branch --force", True),
    ("格式化磁碟", "mkfs.ext4 /dev/sda1", True),
    ("覆寫磁碟", "dd if=/dev/zero of=/dev/sda", True),
    ("關機", "shutdown -h now", True),
    ("清空防火牆", "iptables -F", True),
    ("停用安全服務", "systemctl stop falcon-sensor", True),
    ("一般刪除不攔截", "rm -r build", False),
    ("一般指令不攔截", "ls -la && git status", False),
    ("含 -rf 字樣檔名不攔截", "cat notes-rf.txt", False),
]

failures = []

for label, tool, tool_input, expect_deny in SECRET_CASES:
    event = {"tool_name": tool, "tool_input": tool_input}
    for name, module in (("sensitive", sensitive_secrets), ("harness", harness_secrets), ("integrated", integrated_secrets)):
        got = verdict(module, event)
        if got != expect_deny:
            failures.append(f"secrets/{name}: {label} 預期 {'攔截' if expect_deny else '放行'}，實際相反")

for label, command, expect_deny in DANGER_CASES:
    event = {"tool_name": "Bash", "tool_input": {"command": command}}
    for name, module in (("harness", harness_danger), ("integrated", integrated_danger)):
        got = verdict(module, event)
        if got != expect_deny:
            failures.append(f"danger/{name}: {label} 預期 {'攔截' if expect_deny else '放行'}，實際相反")

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
for filename in ("redact_sensitive_info.py", "block_pii_prompt.py", "pii_patterns.py"):
    sensitive = root / "claude/plugins/sensitive-data-guard/hooks" / filename
    harness = root / "harness/.claude/hooks" / filename
    if sensitive.read_text() != harness.read_text():
        raise SystemExit(f"sensitive-data-guard/{filename} 與共用資料規則不同步")
print("PASS: harness 與 integrated-harness 同源 hooks 行為對齊")
PY
