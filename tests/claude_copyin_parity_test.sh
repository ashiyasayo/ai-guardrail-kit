#!/usr/bin/env bash
set -euo pipefail
# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
export PYTHONUTF8=${PYTHONUTF8:-1}
cd "$(dirname "$0")/.."

# 守護 copy-in（harness/.claude/hooks、integrated-harness/.claude/hooks）與
# marketplace plugin（claude/plugins/{harness,integrated-harness}/hooks）的
# 「非 PII」hook 副本一致，避免兩份平行副本悄悄漂移（PII 三件組另由
# claude_shared_sync_test.sh 以 shared/claude 守護，不在此重複）。
#
# plan_gate.py 現以 __file__ 同時支援 copy-in 與 plugin 安裝位置，因此兩份
# 實作也納入逐字節一致性檢查，不再保留發佈型態特例。
python3 - <<'PY'
import pathlib
import sys

root = pathlib.Path.cwd()
failures = []

# （copy-in 目錄, plugin 目錄, 檔名清單）——僅非 PII、應逐字節相同者
IDENTICAL = [
    ("harness/.claude/hooks", "claude/plugins/harness/hooks",
     ["guard.py", "plan_gate.py", "block_secrets.py", "block_dangerous_commands.py"]),
    ("integrated-harness/.claude/hooks", "claude/plugins/integrated-harness/hooks",
     ["guard.py", "block_secrets.py", "block_dangerous_commands.py",
      "approve_plan.py", "inject_protocol.py", "plan_gate.py"]),
]

for copyin_dir, plugin_dir, filenames in IDENTICAL:
    for filename in filenames:
        copyin = root / copyin_dir / filename
        plugin = root / plugin_dir / filename
        if not copyin.is_file() or not plugin.is_file():
            failures.append(f"缺少檔案：{copyin} 或 {plugin}")
            continue
        if copyin.read_bytes() != plugin.read_bytes():
            failures.append(f"copy-in 與 plugin 不同步：{copyin_dir}/{filename}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
print("PASS: copy-in 與 plugin 的非 PII hook 逐字節一致")
PY
