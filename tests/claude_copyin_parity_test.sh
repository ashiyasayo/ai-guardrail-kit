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
# 唯一合法差異：integrated-harness 的 plan_gate.py 核准命令訊息——copy-in 指向
# 相對路徑 .claude/hooks/approve_plan.py，plugin 指向以 __file__ 動態算出的
# 絕對路徑（避免 ${CLAUDE_PLUGIN_ROOT} 字面文字——該變數只在 Claude Code 內部
# 工具執行環境展開，人類自己的終端機沒有這個變數，貼上字面文字會展開成空字串
# 導致 approve_plan.py 找不到檔案，見已修復的實際故障）。此差異無法消除（copy-in
# 與 plugin 的安裝位置不同，需各自算出可執行的路徑），故以「單一連續差異區塊且
# 涉及 approve_plan.py」精確放行，其餘任何位置的差異都視為漂移而失敗。
python3 - <<'PY'
import difflib
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
      "approve_plan.py", "inject_protocol.py"]),
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

# integrated-harness plan_gate.py：允許唯一的核准路徑差異，且必須是單一連續區塊。
copyin_pg = root / "integrated-harness/.claude/hooks/plan_gate.py"
plugin_pg = root / "claude/plugins/integrated-harness/hooks/plan_gate.py"
if not copyin_pg.is_file() or not plugin_pg.is_file():
    failures.append("缺少 integrated-harness plan_gate.py（copy-in 或 plugin）")
else:
    a = copyin_pg.read_text(encoding="utf-8").splitlines()
    b = plugin_pg.read_text(encoding="utf-8").splitlines()
    blocks = [op for op in difflib.SequenceMatcher(a=a, b=b).get_opcodes() if op[0] != "equal"]
    if len(blocks) != 1:
        failures.append(
            f"integrated-harness plan_gate.py 差異不止一處（{len(blocks)} 個區塊），疑似漂移"
        )
    else:
        _tag, i1, i2, j1, j2 = blocks[0]
        changed = a[i1:i2] + b[j1:j2]
        if not any("approve_plan.py" in line for line in changed):
            failures.append(
                "integrated-harness plan_gate.py 的差異區塊未涉及 approve_plan.py，疑似漂移"
            )

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
print("PASS: copy-in 與 plugin 的非 PII hook 一致（IH plan_gate 核准路徑為已知例外）")
PY
