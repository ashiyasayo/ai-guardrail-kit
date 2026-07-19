#!/usr/bin/env bash
set -euo pipefail
# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$ROOT" python3 - <<'PY'
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import NamedTuple, Optional

root = Path(os.environ["ROOT"])
fixtures = root / "tests/fixtures/claude"


class RunResult(NamedTuple):
    status: int
    decision: Optional[str]
    reason: Optional[str]
    stdout: str
    stderr: str


def fixture(name):
    return json.loads((fixtures / name).read_text())


def event(project, tool="Write", tool_input=None):
    return {
        "cwd": str(project),
        "hook_event_name": "PreToolUse",
        "tool_name": tool,
        "tool_input": tool_input or {"file_path": "src/app.py", "content": "x"},
    }


def run(hook, data, project, home=None):
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project)
    if home is not None:
        env["HOME"] = str(home)
    proc = subprocess.run(
        [sys.executable, str(hook)], input=json.dumps(data), text=True,
        capture_output=True, env=env,
    )
    output = json.loads(proc.stdout) if proc.stdout.strip() else None
    specific = output["hookSpecificOutput"] if output else None
    decision = specific["permissionDecision"] if specific else None
    reason = specific["permissionDecisionReason"] if specific else None
    return RunResult(proc.returncode, decision, reason, proc.stdout, proc.stderr)


def normalize(result):
    status, decision, reason, stdout, stderr = result
    if reason is not None:
        reason = reason.replace(
            'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/approve_plan.py"',
            "python3 .claude/hooks/approve_plan.py",
        )
    return status, decision, reason, stdout, stderr


def assert_pair(legacy, packaged, data, project, home=None):
    old = run(legacy, data, project, home=home)
    new = run(packaged, data, project, home=home)
    assert normalize(old)[:3] == normalize(new)[:3], (
        legacy, packaged, old[:3], new[:3]
    )
    assert old.stderr == new.stderr, (old.stderr, new.stderr)
    return old


def assert_denied(result):
    assert result[0] == 2 or result[1] == "deny", result


def assert_allowed(result):
    assert result.status == 0 and result.decision != "deny", result


# Guard the test harness itself: a hook process that crashes without emitting a
# deny decision is not an allowed operation.
try:
    assert_allowed(RunResult(2, None, None, "", "hook failed"))
except AssertionError:
    pass
else:
    raise AssertionError("assert_allowed accepted a non-zero hook exit")


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
    assert_allowed(assert_pair(legacy_dg, packaged_dg, event(project), project))

    for mode in ("harness", "integrated-harness"):
        legacy = root / mode / ".claude/hooks"
        packaged = root / "claude/plugins" / mode / "hooks"
        assert_denied(assert_pair(
            legacy / "plan_gate.py", packaged / "plan_gate.py", event(project), project
        ))
        allow = fixture("allow.json")
        allow["cwd"] = str(project)
        assert_allowed(assert_pair(
            legacy / "block_dangerous_commands.py",
            packaged / "block_dangerous_commands.py", allow, project,
        ))
        assert_allowed(assert_pair(
            legacy / "block_secrets.py", packaged / "block_secrets.py", allow, project,
        ))
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
        for hook in (legacy / "block_secrets.py", packaged / "block_secrets.py"):
            raw = run(hook, secret, project)
            assert "AKIA1234567890ABCDEF" not in raw.stdout, (hook, raw.stdout)
            assert "AKIA1234567890ABCDEF" not in raw.stderr, (hook, raw.stderr)

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
    assert_allowed(assert_pair(
        integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py",
        event(project), project,
    ))
    plan.write_text(plan.read_text() + "changed\n")
    stale = assert_pair(
        integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py",
        event(project), project,
    )
    assert_denied(stale)
    policy.write_text(policy.read_text().replace("核准模式：strict", "核准模式：light", 1))
    assert_allowed(assert_pair(
        integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py",
        event(project), project,
    ))

# 個人層級政策檔 fallback：專案檔不存在時讀取 ~/.claude/orchestration-policy.md
with tempfile.TemporaryDirectory() as td:
    project = Path(td) / "project"
    (project / ".claude/plan").mkdir(parents=True)
    home = Path(td) / "home"
    (home / ".claude").mkdir(parents=True)
    plan = project / ".claude/plan/decomposition.md"
    plan.write_text(
        "## 已知資訊\n## 缺少的資訊\n【假設】none\n"
        "## 允許修改範圍\n- `src/`\n"
    )
    gates = (integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py")
    template = (root / "integrated-harness/.claude/orchestration-policy.md").read_text()

    # 兩處皆無政策檔：維持 strict fail closed，一般 Bash 攔截（防退化）
    bash_event = event(project, tool="Bash", tool_input={"command": "echo hi"})
    assert_denied(assert_pair(*gates, bash_event, project, home=home))

    # 僅個人層級政策檔（standard）：免核准放行範圍內寫入
    personal = home / ".claude/orchestration-policy.md"
    personal.write_text(template.replace("核准模式：strict", "核准模式：standard", 1))
    assert_allowed(assert_pair(*gates, event(project), project, home=home))

    # 模型修改個人政策檔：以政策檔保護理由攔截
    protect = assert_pair(
        *gates,
        event(project, tool_input={"file_path": str(personal), "content": "x"}),
        project, home=home,
    )
    assert_denied(protect)
    assert "政策檔" in (protect.reason or ""), protect

    # 專案政策檔永遠優先：專案 strict 蓋過個人 standard，仍要求人工核准
    (project / ".claude/orchestration-policy.md").write_text(template)
    assert_denied(assert_pair(*gates, event(project), project, home=home))

    # 範本 allowlist 於 strict 模式可用（回歸：範本必須能被解析器接受）
    digest = hashlib.sha256(plan.read_bytes()).hexdigest()
    (project / ".claude/.plan_approved").write_text(
        json.dumps({"approved_at": time.time(), "plan_sha256": digest})
    )
    allowed_bash = event(
        project, tool="Bash",
        tool_input={"command": "bash tests/claude_guard_test.sh"},
    )
    assert_allowed(assert_pair(*gates, allowed_bash, project, home=home))

for mode in ("harness", "integrated-harness"):
    for name in ("block_dangerous_commands.py", "block_secrets.py"):
        legacy = (root / mode / ".claude/hooks" / name).read_text()
        packaged = (root / "claude/plugins" / mode / "hooks" / name).read_text()
        assert legacy == packaged, (mode, name)

print("PASS: packaged Claude guardrails match legacy behavior")
PY
