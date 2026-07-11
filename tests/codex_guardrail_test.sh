#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
section="${1:-shared}"

if [[ "$section" != shared ]]; then
  printf 'FAIL: unsupported test section: %s\n' "$section" >&2
  exit 1
fi

ROOT="$ROOT" python3 - <<'PY'
import contextlib
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

assert security.dangerous_command(event("allow.json")["tool_input"]["command"]) is None
assert security.dangerous_command(event("dangerous-command.json")["tool_input"]["command"]) == "硬重置"

secret_input = event("secret-write.json")["tool_input"]
content = security.pending_content(secret_input)
assert security.secret_kind(content) == "AWS Access Key"
assert "AKIA1234567890ABCDEF" not in security.secret_kind(content)
assert security.secret_kind("api_key = '${API_KEY}'") is None

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

print("PASS: Codex shared hook protocol and security checks")
PY
