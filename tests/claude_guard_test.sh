#!/usr/bin/env bash
# guard.py dispatcher 行為測試：單一進入點須等價於依序執行三支個別 hook。
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

root = Path(os.environ["ROOT"])
fixtures = root / "tests/fixtures/claude"


def fixture(name, project):
    data = json.loads((fixtures / name).read_text())
    data["cwd"] = str(project)
    return data


def event(project, tool="Write", tool_input=None):
    return {
        "cwd": str(project),
        "hook_event_name": "PreToolUse",
        "tool_name": tool,
        "tool_input": tool_input or {"file_path": "src/app.py", "content": "x"},
    }


def run(hook, data, project, raw_input=None, extra_env=None):
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project)
    env.pop("CLAUDE_SCHEDULED_TASK", None)
    if extra_env:
        env.update(extra_env)
    payload = raw_input if raw_input is not None else json.dumps(data)
    proc = subprocess.run(
        [sys.executable, str(hook)], input=payload, text=True,
        capture_output=True, env=env,
    )
    decision = reason = None
    if proc.stdout.strip():
        specific = json.loads(proc.stdout)["hookSpecificOutput"]
        decision, reason = specific["permissionDecision"], specific["permissionDecisionReason"]
    return proc.returncode, decision, reason, proc.stdout, proc.stderr


def assert_allowed(result):
    status, decision, _, _, _ = result
    assert status == 0 and decision != "deny", result


def assert_denied_json(result, keyword):
    status, decision, reason, _, _ = result
    assert status == 0 and decision == "deny" and keyword in reason, result


# --- 註冊契約：四個設定檔都只註冊 guard.py 一條 PreToolUse 規則 ---
REGISTRATIONS = (
    ("harness/.claude/settings.json", "Write|Edit|MultiEdit|NotebookEdit|Bash"),
    ("integrated-harness/.claude/settings.json", "*"),
    ("claude/plugins/harness/hooks/hooks.json", "Write|Edit|MultiEdit|NotebookEdit|Bash"),
    ("claude/plugins/integrated-harness/hooks/hooks.json", "*"),
)
for relative, matcher in REGISTRATIONS:
    config = json.loads((root / relative).read_text())
    groups = config["hooks"]["PreToolUse"]
    assert len(groups) == 1, (relative, groups)
    assert groups[0]["matcher"] == matcher, (relative, groups[0]["matcher"])
    commands = [hook["command"] for hook in groups[0]["hooks"]]
    assert len(commands) == 1 and "guard.py" in commands[0], (relative, commands)

# --- copy-in 版與 marketplace 版的 guard.py 必須逐位元組相同 ---
for mode in ("harness", "integrated-harness"):
    legacy = (root / mode / ".claude/hooks/guard.py").read_text()
    packaged = (root / "claude/plugins" / mode / "hooks/guard.py").read_text()
    assert legacy == packaged, mode

# --- harness 模式：JSON deny 語意（guard.py 已升級為 hookSpecificOutput 協定） ---
with tempfile.TemporaryDirectory() as td:
    project = Path(td) / "project"
    (project / ".claude").mkdir(parents=True)
    for guard in (root / "harness/.claude/hooks/guard.py",
                  root / "claude/plugins/harness/hooks/guard.py"):
        # 尚未核准：一般寫入被計畫閘門攔截
        assert_denied_json(run(guard, event(project), project), "計畫閘門")
        # 危險指令：紅線攔截優先於計畫閘門
        assert_denied_json(run(guard, fixture("dangerous-command.json", project), project), "危險指令攔截")
        # 排程任務：無核准旗標也放行一般寫入（僅豁免計畫閘門）
        assert_allowed(run(guard, event(project), project, extra_env={"CLAUDE_SCHEDULED_TASK": "1"}))
        # 排程任務：紅線指令與憑證攔截不因排程身分而豁免
        assert_denied_json(run(
            guard, fixture("dangerous-command.json", project), project,
            extra_env={"CLAUDE_SCHEDULED_TASK": "1"},
        ), "危險指令攔截")
        result = run(
            guard, fixture("secret-write.json", project), project,
            extra_env={"CLAUDE_SCHEDULED_TASK": "1"},
        )
        assert_denied_json(result, "憑證攔截")
        assert "AKIA1234567890ABCDEF" not in result[3] + result[4], result
        # 憑證寫入：即使已核准仍攔截，且憑證值不得外洩
        (project / ".claude/.plan_approved").touch()
        result = run(guard, fixture("secret-write.json", project), project)
        assert_denied_json(result, "憑證攔截")
        assert "AKIA1234567890ABCDEF" not in result[3] + result[4], result
        # 已核准：唯讀指令與一般寫入放行
        assert_allowed(run(guard, fixture("allow.json", project), project))
        assert_allowed(run(guard, event(project), project))
        # 模型不得操作核准旗標
        assert_denied_json(run(guard, event(
            project, "Bash", {"command": "touch .claude/.plan_approved"}), project), "計畫閘門")
        # 輸入非 JSON：fail closed（仍是 stderr + exit 2，未變）
        status, _, _, _, stderr = run(guard, None, project, raw_input="{bad")
        assert status == 2 and stderr, (status, stderr)
        (project / ".claude/.plan_approved").unlink()

# --- integrated-harness 模式：JSON deny 語意 ---
with tempfile.TemporaryDirectory() as td:
    project = Path(td) / "project"
    (project / ".claude/plan").mkdir(parents=True)
    shutil.copy(root / "integrated-harness/.claude/orchestration-policy.md",
                project / ".claude/orchestration-policy.md")
    plan = project / ".claude/plan/decomposition.md"
    plan.write_text(
        "## 已知資訊\n## 缺少的資訊\n【假設】none\n## 允許修改範圍\n- `src/`\n"
    )
    digest = hashlib.sha256(plan.read_bytes()).hexdigest()
    (project / ".claude/.plan_approved").write_text(
        json.dumps({"approved_at": time.time(), "plan_sha256": digest})
    )
    for guard in (root / "integrated-harness/.claude/hooks/guard.py",
                  root / "claude/plugins/integrated-harness/hooks/guard.py"):
        # 拆解完成且已核准：範圍內寫入與唯讀指令放行
        assert_allowed(run(guard, event(project), project))
        assert_allowed(run(guard, fixture("allow.json", project), project))
        # 危險指令：不因核准而豁免
        assert_denied_json(run(guard, fixture("dangerous-command.json", project), project), "危險指令攔截")
        # 憑證寫入：dispatcher 順序上，憑證檢查先於範圍檢查，且憑證值不得外洩
        result = run(guard, fixture("secret-write.json", project), project)
        assert_denied_json(result, "憑證攔截")
        assert "AKIA1234567890ABCDEF" not in result[3] + result[4], result
        # 範圍外寫入：計畫閘門攔截
        assert_denied_json(run(guard, event(
            project, "Write", {"file_path": "other/app.py", "content": "x"}), project), "計畫閘門")
        # 排程任務：範圍外寫入也放行（僅豁免計畫閘門）
        assert_allowed(run(guard, event(
            project, "Write", {"file_path": "other/app.py", "content": "x"}), project,
            extra_env={"CLAUDE_SCHEDULED_TASK": "1"}))
        # 排程任務：紅線指令與憑證攔截不因排程身分而豁免
        assert_denied_json(run(
            guard, fixture("dangerous-command.json", project), project,
            extra_env={"CLAUDE_SCHEDULED_TASK": "1"},
        ), "危險指令攔截")
        result = run(
            guard, fixture("secret-write.json", project), project,
            extra_env={"CLAUDE_SCHEDULED_TASK": "1"},
        )
        assert_denied_json(result, "憑證攔截")
        assert "AKIA1234567890ABCDEF" not in result[3] + result[4], result
        # 模型不得操作核准旗標
        assert_denied_json(run(guard, event(
            project, "Bash", {"command": "rm .claude/.plan_approved"}), project), "核准旗標")
        # 輸入非 JSON：fail closed
        status, _, _, _, stderr = run(guard, None, project, raw_input="{bad")
        assert status == 2 and stderr, (status, stderr)

print("PASS: guard dispatcher matches individual hook behavior")
PY
