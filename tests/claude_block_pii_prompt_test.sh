#!/usr/bin/env bash
# block_pii_prompt.py 行為測試：UserPromptSubmit 階段偵測疑似個資即整段阻擋，
# 不放行、不改寫（Claude Code 的 UserPromptSubmit 不支援改寫提示內容）。
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


def run(hook, data):
    proc = subprocess.run(
        [sys.executable, str(hook)], input=json.dumps(data), text=True,
        capture_output=True,
    )
    output = json.loads(proc.stdout) if proc.stdout.strip() else None
    return proc, output


for base in (
    root / "integrated-harness/.claude/hooks",
    root / "claude/plugins/integrated-harness/hooks",
    root / "harness/.claude/hooks",
    root / "claude/plugins/harness/hooks",
):
    hook = base / "block_pii_prompt.py"

    pii = fixture("pii-prompt.json")
    proc, output = run(hook, pii)
    assert proc.returncode == 0, (hook, proc.stdout, proc.stderr)
    assert output is not None, (hook, proc.stdout)
    assert output["decision"] == "block", output
    assert "A123456789" not in output.get("reason", ""), output
    assert "A123456789" not in proc.stdout, proc.stdout

    address = fixture("pii-address-prompt.json")
    proc, output = run(hook, address)
    assert proc.returncode == 0, (hook, proc.stdout, proc.stderr)
    assert output is not None, (hook, proc.stdout)
    assert output["decision"] == "block", output
    assert "地址" in output.get("reason", ""), output

    student = fixture("pii-student-prompt.json")
    proc, output = run(hook, student)
    assert proc.returncode == 0, (hook, proc.stdout, proc.stderr)
    assert output is not None, (hook, proc.stdout)
    assert output["decision"] == "block", output
    assert "學號" in output.get("reason", ""), output

    passport = fixture("pii-passport-prompt.json")
    proc, output = run(hook, passport)
    assert proc.returncode == 0, (hook, proc.stdout, proc.stderr)
    assert output is not None, (hook, proc.stdout)
    assert output["decision"] == "block", output
    assert "護照號碼" in output.get("reason", ""), output

    clean = fixture("clean-prompt.json")
    proc, output = run(hook, clean)
    assert proc.returncode == 0, (hook, proc.stdout, proc.stderr)
    assert output is None, output

print("PASS: block_pii_prompt 行為符合預期")
PY
