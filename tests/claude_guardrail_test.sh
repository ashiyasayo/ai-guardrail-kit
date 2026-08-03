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
import re
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
        # 開發版用相對路徑、封裝版用動態絕對路徑，兩者實際指令不同但等價；
        # 比對前抹除路徑差異，只留 approve_plan.py 呼叫本身。
        reason = re.sub(
            r'python3\s+"?[^`]*approve_plan\.py"?',
            "python3 approve_plan.py",
            reason,
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


def assert_denied(result, reason_contains):
    """驗證 deny 決策，並要求原因含指定片段。

    只比對 deny 會讓任何無關原因造成的普遍性攔截（例如 cwd 解析失敗）
    也滿足斷言，即使受測關卡完全失效仍是綠燈；故 reason 為必填。
    """
    assert result[0] == 2 or result[1] == "deny", result
    # 攔截原因可能來自 JSON 的 permissionDecisionReason，或 exit code 2 的 stderr
    # 回饋（harness 版 plan_gate 走後者），兩處都要納入比對。
    detail = (result.reason or "") + result.stderr
    assert reason_contains in detail, (reason_contains, result)


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
    assert_denied(
        assert_pair(legacy_dg, packaged_dg, event(project), project),
        "找不到拆解產出物",
    )
    plan = project / ".claude/plan/decomposition.md"
    plan.write_text("## 已知資訊\n## 缺少的資訊\n")
    assert_denied(
        assert_pair(legacy_dg, packaged_dg, event(project), project),
        "拆解產出物不完整",
    )
    plan.write_text("## 已知資訊\n## 缺少的資訊\n【假設】none\n")
    assert_allowed(assert_pair(legacy_dg, packaged_dg, event(project), project))

    # 兩種模式此時的攔截原因不同：harness 缺核准旗標，integrated-harness 另要求
    # 拆解含 `## 允許修改範圍` 標記（此處尚未加入），故分別比對各自的原因。
    plan_gate_reasons = {
        "harness": "本操作屬寫入性行為",
        "integrated-harness": "拆解文件缺少必要標記：## 允許修改範圍",
    }
    for mode in ("harness", "integrated-harness"):
        legacy = root / mode / ".claude/hooks"
        packaged = root / "claude/plugins" / mode / "hooks"
        assert_denied(assert_pair(
            legacy / "plan_gate.py", packaged / "plan_gate.py", event(project), project
        ), plan_gate_reasons[mode])
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
        ), "危險指令攔截：")
        secret = fixture("secret-write.json")
        secret["cwd"] = str(project)
        result = assert_pair(
            legacy / "block_secrets.py", packaged / "block_secrets.py", secret, project
        )
        assert_denied(result, "憑證攔截：")
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
    assert_denied(strict, "尚未取得人類核准")
    digest = hashlib.sha256(plan.read_bytes()).hexdigest()
    approval = project / ".claude/.plan_approved"
    approval.write_text(json.dumps({"approved_at": time.time(), "plan_sha256": digest}))
    assert_allowed(assert_pair(
        integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py",
        event(project), project,
    ))
    # 變動後的計畫必須仍然合法，否則會攔在「範圍格式錯誤」而驗不到 SHA-256 比對
    plan.write_text(plan.read_text() + "- `docs/`\n")
    stale = assert_pair(
        integrated_legacy / "plan_gate.py", integrated_packaged / "plan_gate.py",
        event(project), project,
    )
    assert_denied(stale, "拆解文件與核准版本不一致")
    policy.write_text(policy.read_text().replace("- Approval Mode: strict", "- Approval Mode: light", 1))
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
    assert_denied(
        assert_pair(*gates, bash_event, project, home=home),
        "strict 模式禁止一般 Bash",
    )

    # 僅個人層級政策檔（standard）：免核准放行範圍內寫入
    personal = home / ".claude/orchestration-policy.md"
    personal.write_text(template.replace("- Approval Mode: strict", "- Approval Mode: standard", 1))
    assert_allowed(assert_pair(*gates, event(project), project, home=home))

    # 模型修改個人政策檔：以政策檔保護理由攔截
    protect = assert_pair(
        *gates,
        event(project, tool_input={"file_path": str(personal), "content": "x"}),
        project, home=home,
    )
    assert_denied(protect, "編排政策檔只能由人類修改")

    # 專案政策檔永遠優先：專案 strict 蓋過個人 standard，仍要求人工核准
    (project / ".claude/orchestration-policy.md").write_text(template)
    assert_denied(
        assert_pair(*gates, event(project), project, home=home),
        "尚未取得人類核准",
    )

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
