#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

python3 - <<'PY'
import json
import os
import re
from pathlib import Path

root = Path(os.environ["ROOT"])
marketplace_path = root / "claude/.claude-plugin/marketplace.json"
assert marketplace_path.is_file(), f"missing {marketplace_path.relative_to(root)}"

marketplace = json.loads(marketplace_path.read_text())
assert marketplace["name"] == "ai-guardrail-kit"

modes = ("decomposition-gate", "harness", "integrated-harness")
plugins = marketplace["plugins"]
assert len(plugins) == len(modes)
assert {entry["name"] for entry in plugins} == set(modes)

for mode in modes:
    entry = next(item for item in plugins if item["name"] == mode)
    assert entry["source"] == f"./plugins/{mode}"

    plugin_root = root / "claude/plugins" / mode
    manifest_path = plugin_root / ".claude-plugin/plugin.json"
    hooks_path = plugin_root / "hooks/hooks.json"
    assert manifest_path.is_file(), f"missing {manifest_path.relative_to(root)}"
    assert hooks_path.is_file(), f"missing {hooks_path.relative_to(root)}"

    manifest = json.loads(manifest_path.read_text())
    assert manifest["name"] == mode
    assert manifest["version"] == "0.1.0"

    registration = json.loads(hooks_path.read_text())
    commands = [
        hook["command"]
        for groups in registration["hooks"].values()
        for group in groups
        for hook in group["hooks"]
    ]
    assert commands, f"no hook commands registered for {mode}"
    prefix = 'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/'
    for command in commands:
        assert command.startswith(prefix), f"non-plugin-root command: {command}"
        match = re.fullmatch(r'python3 "\$\{CLAUDE_PLUGIN_ROOT\}/hooks/([^"/]+\.py)"', command)
        assert match, f"unexpected hook command: {command}"
        executable = plugin_root / "hooks" / match.group(1)
        assert executable.is_file(), f"missing executable {executable.relative_to(root)}"

    for runtime_file in plugin_root.rglob("*"):
        if runtime_file.is_file():
            assert b"$CLAUDE_PROJECT_DIR/.claude/hooks/" not in runtime_file.read_bytes(), (
                f"legacy hook path in {runtime_file.relative_to(root)}"
            )

print("PASS: Claude marketplace packages are complete")
PY
