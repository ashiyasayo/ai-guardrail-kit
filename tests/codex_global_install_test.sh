#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"
ln -s "$repo/tests/helpers/fake-codex" "$tmp/bin/codex"
export PATH="$tmp/bin:$PATH"
export AI_GUARDRAIL_TEST_STATE="$tmp/state"
export HOME="$tmp/home"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
hooks="$HOME/.codex/hooks.json"
policy="$HOME/.codex/guardrail/orchestration-policy.md"
seed_hooks() {
  mkdir -p "$(dirname "$hooks")"
  cat > "$hooks" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "exec_command",
        "hooks": [
          {"type": "command", "command": "python3 -- /opt/unrelated.py"}
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": ".*",
        "hooks": [
          {"type": "command", "command": "python3 -- /opt/approval.py"}
        ]
      }
    ]
  }
}
JSON
}

assert_global_hooks() {
  python3 - "$hooks" <<'PY' || fail 'global hook structure is invalid'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
groups = data["hooks"]["PreToolUse"]
commands = [hook["command"] for group in groups for hook in group["hooks"]]
assert "python3 -- /opt/unrelated.py" in commands
for name in ("plan_gate.py", "block_dangerous_commands.py", "block_secrets.py"):
    matches = [command for command in commands if name in command]
    assert len(matches) == 1, (name, matches)
    assert matches[0].startswith("AI_GUARDRAIL_GLOBAL_DEFAULT=1 python3 -- "), matches[0]
assert data["hooks"]["PermissionRequest"][0]["hooks"][0]["command"] == "python3 -- /opt/approval.py"
PY
}

seed_hooks
before=$(sha256sum "$hooks")
"$repo/scripts/install-codex-global-integrated-harness" "$repo" >/dev/null
"$repo/scripts/verify-codex-global-integrated-harness" "$repo" >/dev/null || fail 'first install did not verify'
assert_global_hooks
cmp -s "$repo/codex/plugins/integrated-harness/orchestration-policy.md" "$policy" || fail 'personal policy not installed'

installed=$(sha256sum "$hooks")
"$repo/scripts/install-codex-global-integrated-harness" "$repo" >/dev/null
[[ $installed == "$(sha256sum "$hooks")" ]] || fail 'repeated install changed global hooks'

"$repo/scripts/install-codex-global-integrated-harness" --remove "$repo" >/dev/null
"$repo/scripts/verify-codex-global-integrated-harness" --no-installed "$repo" >/dev/null || fail 'removal did not verify'
[[ $before == "$(sha256sum "$hooks")" ]] || fail 'removal did not restore unrelated global hooks'
"$repo/scripts/install-codex-global-integrated-harness" --remove "$repo" >/dev/null
[[ $before == "$(sha256sum "$hooks")" ]] || fail 'repeated removal changed global hooks'

unset HOME
export HOME="$tmp/rollback-home"
hooks="$HOME/.codex/hooks.json"
policy="$HOME/.codex/guardrail/orchestration-policy.md"
seed_hooks
rollback_before=$(sha256sum "$hooks")
export AI_GUARDRAIL_TEST_FAIL_GLOBAL_VERIFY=1
if "$repo/scripts/install-codex-global-integrated-harness" "$repo" >/dev/null 2>&1; then
  fail 'verification failure did not fail install'
fi
unset AI_GUARDRAIL_TEST_FAIL_GLOBAL_VERIFY
[[ $rollback_before == "$(sha256sum "$hooks")" ]] || fail 'verification failure did not roll back hooks'
[[ ! -e $policy ]] || fail 'verification failure did not roll back created policy'

printf 'PASS: global Codex integrated-harness installation\n'