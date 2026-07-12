#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$ROOT" python3 - <<'PY'
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(os.environ["ROOT"])
fixtures = root / "tests/fixtures/claude"


def fixture(name):
    return json.loads((fixtures / name).read_text())


def event(project, tool="Write", tool_input=None):
    return {
        "cwd": str(project),
        "hook_event_name": "PreToolUse",
        "tool_name": tool,
        "tool_input": tool_input or {"file_path": "src/app.py", "content": "x"},
    }


def run(hook, data, project):
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project)
    proc = subprocess.run(
        ["python3", str(hook)], input=json.dumps(data), text=True,
        capture_output=True, env=env,
    )
    output = json.loads(proc.stdout) if proc.stdout.strip() else None
    specific = output["hookSpecificOutput"] if output else None
    decision = specific["permissionDecision"] if specific else None
    reason = specific["permissionDecisionReason"] if specific else None
    return proc.returncode, decision, reason, proc.stderr


def normalize(result):
    status, decision, reason, stderr = result
    if reason is not None:
        reason = reason.replace(
            'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/approve_plan.py"',
            "python3 .claude/hooks/approve_plan.py",
        )
    return status, decision, reason, stderr


def assert_pair(legacy, packaged, data, project):
    old = run(legacy, data, project)
    new = run(packaged, data, project)
    assert normalize(old)[:3] == normalize(new)[:3], (
        legacy, packaged, old[:3], new[:3]
    )
    assert old[3] == new[3], (old[3], new[3])
    return old


def assert_denied(result):
    assert result[0] == 2 or result[1] == "deny", result


with tempfile.TemporaryDirectory() as td:
    project = Path(td) / "project"
    (project / ".claude/plan").mkdir(parents=True)

    legacy_dg = root / "decomposition-gate/.claude/hooks/decomposition_gate.py"
    packaged_dg = root / "claude/plugins/decomposition-gate/hooks/decomposition_gate.py"
    assert_denied(assert_pair(legacy_dg, packaged_dg, event(project), project))
    plan = project / ".claude/plan/decomposition.md"
    plan.write_text("## 已知資訊\n## 缺少的資訊\n")
    assert_denied(assert_pair(legacy_dg, packaged_dg, event(project), project))
    plan.write_text("## 已知資訊\n## 缺少的資訊\n【假設】none\n")
    assert assert_pair(legacy_dg, packaged_dg, event(project), project)[1] is None

    for mode in ("harness", "integrated-harness"):
        legacy = root / mode / ".claude/hooks"
        packaged = root / "claude/plugins" / mode / "hooks"
        assert_denied(assert_pair(
            legacy / "plan_gate.py", packaged / "plan_gate.py", event(project), project
        ))
        allow = fixture("allow.json")
        allow["cwd"] = str(project)
        assert assert_pair(
            legacy / "block_dangerous_commands.py",
            packaged / "block_dangerous_commands.py", allow, project,
        )[1] is None
        assert assert_pair(
            legacy / "block_secrets.py", packaged / "block_secrets.py", allow, project,
        )[1] is None
        dangerous = fixture("dangerous-command.json")
        dangerous["cwd"] = str(project)
        assert_denied(assert_pair(
            legacy / "block_dangerous_commands.py",
            packaged / "block_dangerous_commands.py", dangerous, project,
        ))
        secret = fixture("secret-write.json")
        secret["cwd"] = str(project)
        result = assert_pair(
            legacy / "block_secrets.py", packaged / "block_secrets.py", secret, project
        )
        assert_denied(result)
        assert "AKIA1234567890ABCDEF" not in json.dumps(result, ensure_ascii=False)

    integrated_legacy = root / "integrated-harness/.claude/hooks"
    integrated_packaged = root / "claude/plugins/integrated-harness/hooks"
    policy = project / ".claude/orchestration-policy.md"
    shutil.copy(root / "integrated-harness/.claude/orchestration-policy.md", policy)
    plan.write_text(
        "## 已知資訊\n## 缺少的資訊\n【假設】none\n"
        "## 允許修改範圍\n- `src/`\n"
    )
    strict = assert_pair(
        integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py",
        event(project), project,
    )
    assert_denied(strict)
    digest = hashlib.sha256(plan.read_bytes()).hexdigest()
    approval = project / ".claude/.plan_approved"
    approval.write_text(json.dumps({"approved_at": time.time(), "plan_sha256": digest}))
    assert assert_pair(
        integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py",
        event(project), project,
    )[1] is None
    plan.write_text(plan.read_text() + "changed\n")
    stale = assert_pair(
        integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py",
        event(project), project,
    )
    assert_denied(stale)
    policy.write_text(policy.read_text().replace("核准模式：strict", "核准模式：light", 1))
    assert assert_pair(
        integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py",
        event(project), project,
    )[1] is None

for mode in ("harness", "integrated-harness"):
    for name in ("block_dangerous_commands.py", "block_secrets.py"):
        legacy = (root / mode / ".claude/hooks" / name).read_text()
        packaged = (root / "claude/plugins" / mode / "hooks" / name).read_text()
        assert legacy == packaged, (mode, name)

print("PASS: packaged Claude guardrails match legacy behavior")
PY
