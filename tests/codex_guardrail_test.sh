#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
section="${1:-all}"

if [[ "$section" != shared && "$section" != modes && "$section" != all ]]; then
  printf 'FAIL: unsupported test section: %s\n' "$section" >&2
  exit 1
fi

if [[ "$section" == shared || "$section" == all ]]; then
ROOT="$ROOT" python3 - <<'PY'
import contextlib
import ast
import importlib.util
import io
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT"])

def load_module(name):
    path = root / "shared" / "codex" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

protocol = load_module("hook_protocol")
security = load_module("security_checks")
fixtures = root / "tests" / "fixtures" / "codex"

for python_file in (root / "shared" / "codex").glob("*.py"):
    ast.parse(python_file.read_text(), filename=str(python_file), feature_version=(3, 9))

def event(name):
    return json.loads((fixtures / name).read_text())

assert protocol.load_event(io.StringIO(json.dumps(event("allow.json")))) == event("allow.json")
assert protocol.project_root(event("allow.json")) == Path("/tmp").resolve()

out, err = io.StringIO(), io.StringIO()
try:
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        protocol.load_event(io.StringIO("not-json"))
except SystemExit as exc:
    assert exc.code == 0, exc.code
else:
    raise AssertionError("malformed JSON did not fail closed")
denial = json.loads(out.getvalue())
assert denial == {
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "Invalid Codex hook input",
    }
}
assert err.getvalue() == ""

class BrokenStream:
    def __init__(self, error):
        self.error = error

    def read(self, *args, **kwargs):
        raise self.error

for error in (OSError("read failed"), UnicodeError("bad unicode"), RecursionError("too deep")):
    out, err = io.StringIO(), io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            protocol.load_event(BrokenStream(error))
    except SystemExit as exc:
        assert exc.code == 0
    else:
        raise AssertionError(f"{type(error).__name__} did not fail closed")
    assert json.loads(out.getvalue()) == denial
    assert err.getvalue() == ""

for field in ("cwd", "model", "permission_mode", "session_id", "tool_name", "tool_use_id", "turn_id"):
    invalid = event("allow.json")
    invalid[field] = 7
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            protocol.load_event(io.StringIO(json.dumps(invalid)))
    except SystemExit:
        pass
    else:
        raise AssertionError(f"non-string {field} was accepted")

unfamiliar_mode = event("allow.json")
unfamiliar_mode["permission_mode"] = "futurePermissionMode"
try:
    with contextlib.redirect_stdout(io.StringIO()):
        loaded_unfamiliar_mode = protocol.load_event(io.StringIO(json.dumps(unfamiliar_mode)))
except SystemExit as exc:
    raise AssertionError("unfamiliar nonempty permission mode was denied") from exc
assert loaded_unfamiliar_mode == unfamiliar_mode

for invalid_mode in ("",):
    invalid = event("allow.json")
    invalid["permission_mode"] = invalid_mode
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            protocol.load_event(io.StringIO(json.dumps(invalid)))
    except SystemExit:
        pass
    else:
        raise AssertionError(f"invalid permission mode {invalid_mode!r} was accepted")

invalid = event("allow.json")
invalid["tool_input"] = []
try:
    with contextlib.redirect_stdout(io.StringIO()):
        protocol.load_event(io.StringIO(json.dumps(invalid)))
except SystemExit:
    pass
else:
    raise AssertionError("non-dict tool input was accepted")

assert security.dangerous_command(event("allow.json")["tool_input"]["command"]) is None
assert security.dangerous_command(event("dangerous-command.json")["tool_input"]["command"]) == "硬重置"

secret_input = event("secret-write.json")["tool_input"]
content = security.pending_content(secret_input)
assert security.secret_kind(content) == "AWS Access Key"
assert "AKIA1234567890ABCDEF" not in security.secret_kind(content)
assert security.secret_kind("api_key = '${API_KEY}'") is None

out, err = io.StringIO(), io.StringIO()
try:
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        protocol.deny(security.secret_kind(security.pending_content(secret_input)))
except SystemExit as exc:
    assert exc.code == 0
else:
    raise AssertionError("secret denial did not terminate")
secret_denial = json.loads(out.getvalue())
assert secret_denial["hookSpecificOutput"]["permissionDecisionReason"] == "AWS Access Key"
assert "AKIA1234567890ABCDEF" not in out.getvalue()
assert "AKIA1234567890ABCDEF" not in err.getvalue()

missing_root = event("allow.json")
missing_root.pop("cwd")
out = io.StringIO()
try:
    with contextlib.redirect_stdout(out):
        protocol.project_root(missing_root)
except SystemExit as exc:
    assert exc.code == 0
else:
    raise AssertionError("missing cwd did not fail closed")
assert "deny" in out.getvalue()

root_cases = [
    str(root / "does-not-exist"),
    str(root / "shared" / "codex" / "hook_protocol.py"),
    "",
    7,
]
for invalid_cwd in root_cases:
    invalid_root = event("allow.json")
    invalid_root["cwd"] = invalid_cwd
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            protocol.project_root(invalid_root)
    except SystemExit as exc:
        assert exc.code == 0
    else:
        raise AssertionError(f"invalid project root {invalid_cwd!r} was accepted")
    assert json.loads(out.getvalue())["hookSpecificOutput"]["permissionDecision"] == "deny"

print("PASS: Codex shared hook protocol and security checks")
PY
fi

if [[ "$section" == modes || "$section" == all ]]; then
ROOT="$ROOT" python3 - <<'PY'
import ast, hashlib, json, os, shutil, subprocess, tempfile, time
from pathlib import Path

root = Path(os.environ["ROOT"])
plugins = root / "codex" / "plugins"

def event(cwd, tool="Write", tool_input=None):
    return {"cwd": str(cwd), "hook_event_name": "PreToolUse", "model": "test",
            "permission_mode": "default", "session_id": "s", "tool_input": tool_input or {"file_path": "src/app.py", "content": "x"},
            "tool_name": tool, "tool_use_id": "u", "transcript_path": "", "turn_id": "t"}

def run(hook, data):
    proc = subprocess.run(["python3", str(hook)], input=json.dumps(data), text=True, capture_output=True)
    assert proc.returncode == 0, (hook, proc.stderr)
    return json.loads(proc.stdout)["hookSpecificOutput"] if proc.stdout.strip() else None

def denied(hook, data):
    result = run(hook, data)
    assert result and result["permissionDecision"] == "deny", (hook, result)
    return result["permissionDecisionReason"]

for source in plugins.rglob("*.py"):
    ast.parse(source.read_text(), filename=str(source), feature_version=(3, 9))

with tempfile.TemporaryDirectory() as td:
    td = Path(td); install = td / "installed"
    shutil.copytree(plugins, install)
    project = td / "project"; project.mkdir()
    guard = project / ".codex" / "guardrail"; (guard / "plan").mkdir(parents=True)

    dg = install / "decomposition-gate/hooks/decomposition_gate.py"
    denied(dg, event(project))
    plan = guard / "plan/decomposition.md"
    assert run(dg, event(project, tool_input={"file_path": str(plan), "content": "draft"})) is None
    plan.write_text("## 已知資訊\n## 缺少的資訊\n")
    denied(dg, event(project))
    plan.write_text("## 已知資訊\n## 缺少的資訊\n【假設】x\n")
    assert run(dg, event(project)) is None

    hp = install / "harness/hooks/plan_gate.py"
    approve = install / "harness/scripts/approve_plan.py"
    approval = guard / "approval.json"
    denied(hp, event(project))
    subprocess.run(["python3", str(approve), str(project)], check=True, capture_output=True, text=True)
    assert run(hp, event(project)) is None
    approval.write_text(json.dumps({"plan_sha256": hashlib.sha256(plan.read_bytes()).hexdigest(), "approved_at": time.time()-3601}))
    denied(hp, event(project))
    approval.write_text(json.dumps({"plan_sha256": hashlib.sha256(plan.read_bytes()).hexdigest(), "approved_at": time.time()+61}))
    denied(hp, event(project))
    denied(hp, event(project, tool_input={"file_path": str(approval), "content": "{}"}))
    subprocess.run(["python3", str(approve), str(project)], check=True, capture_output=True, text=True)
    dangerous = install / "harness/hooks/block_dangerous_commands.py"
    denied(dangerous, event(project, "Bash", {"command": "git reset --hard"}))
    secrets = install / "harness/hooks/block_secrets.py"
    denied(secrets, event(project, tool_input={"file_path": "x", "content": "AWS=AKIA1234567890ABCDEF"}))

    ip = install / "integrated-harness/hooks/plan_gate.py"
    policy = guard / "orchestration-policy.md"
    shutil.copy(install / "integrated-harness/orchestration-policy.md", policy)
    plan.write_text("## 已知資訊\n## 缺少的資訊\n【假設】x\n## 允許修改範圍\n- `src/`\n")
    denied(ip, event(project))
    ia = install / "integrated-harness/scripts/approve_plan.py"
    subprocess.run(["python3", str(ia), str(project)], check=True, capture_output=True, text=True)
    assert run(ip, event(project)) is None
    denied(ip, event(project, tool_input={"file_path": "other/x", "content": "x"}))
    plan.write_text(plan.read_text()+"changed\n")
    denied(ip, event(project))
    policy.write_text(policy.read_text().replace("strict", "light", 1))
    assert run(ip, event(project, tool_input={"file_path": "other/x", "content": "x"})) is None
    policy.unlink()
    denied(ip, event(project))

print("PASS: Codex standalone guardrail modes (22 assertions)")
PY
fi
