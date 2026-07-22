#!/usr/bin/env bash
# redact_sensitive_info.py 行為測試：個資去識別化（改寫後放行，非阻擋）。
set -euo pipefail
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
export PYTHONUTF8=${PYTHONUTF8:-1}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$ROOT" python3 - <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

root = Path(os.environ["ROOT"])
fixtures = root / "tests/fixtures/claude"


def fixture(name):
    return json.loads((fixtures / name).read_text())


def run(hook, data, env=None):
    run_env = os.environ.copy()
    if env:
        run_env.update(env)
    proc = subprocess.run(
        [sys.executable, str(hook)], input=json.dumps(data), text=True,
        capture_output=True, env=run_env,
    )
    output = json.loads(proc.stdout) if proc.stdout.strip() else None
    specific = output["hookSpecificOutput"] if output else None
    return proc, specific


for base in (
    root / "integrated-harness/.claude/hooks",
    root / "claude/plugins/integrated-harness/hooks",
):
    hook = base / "redact_sensitive_info.py"

    # 命中個資：allow + updatedInput 改寫內容，原文不得外流到 stdout/stderr
    data = fixture("pii-write.json")
    proc, specific = run(hook, data)
    assert proc.returncode == 0, (hook, proc.stdout, proc.stderr)
    assert specific is not None, (hook, proc.stdout)
    assert specific["permissionDecision"] == "allow", specific
    updated = specific.get("updatedInput")
    assert updated is not None, specific
    content = updated["content"]
    assert "A123456789" not in content, content
    assert "0912345678" not in content, content
    assert "test.user@example.com" not in content, content
    assert "A123456789" not in proc.stdout, proc.stdout
    assert "0912345678" not in proc.stdout, proc.stdout

    # 未命中個資：不輸出任何 hookSpecificOutput（放行、不改寫）
    clean = fixture("allow.json")
    proc, specific = run(hook, clean)
    assert proc.returncode == 0, (hook, proc.stdout, proc.stderr)
    assert specific is None, specific

    # guard.py 統一進入點也要能觸發改寫（同一輸入經 guard 仍得到 updatedInput）；
    # 以排程任務環境變數豁免 plan_gate，聚焦驗證本 hook 的改寫行為有掛載到 guard。
    guard = base / "guard.py"
    proc, specific = run(guard, data, env={"CLAUDE_SCHEDULED_TASK": "1"})
    assert proc.returncode == 0, (guard, proc.stdout, proc.stderr)
    assert specific is not None and specific.get("updatedInput") is not None, (guard, proc.stdout)

print("PASS: redact_sensitive_info 行為符合預期")
PY
