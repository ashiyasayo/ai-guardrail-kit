#!/usr/bin/env bash
set -euo pipefail
# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

python3 - <<'PY'
import json
import os
import re
from pathlib import Path

root = Path(os.environ["ROOT"])
marketplace_path = root / ".claude-plugin/marketplace.json"
assert marketplace_path.is_file(), f"missing {marketplace_path.relative_to(root)}"

marketplace = json.loads(marketplace_path.read_text())
assert marketplace["name"] == "ai-guardrail-kit"

modes = ("decomposition-gate", "sensitive-data-guard", "harness", "integrated-harness")
SEMVER_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
plugins = marketplace["plugins"]
assert len(plugins) == len(modes)
assert {entry["name"] for entry in plugins} == set(modes)

for mode in modes:
    entry = next(item for item in plugins if item["name"] == mode)
    assert entry["source"] == f"./claude/plugins/{mode}"

    plugin_root = root / "claude/plugins" / mode
    manifest_path = plugin_root / ".claude-plugin/plugin.json"
    hooks_path = plugin_root / "hooks/hooks.json"
    assert manifest_path.is_file(), f"missing {manifest_path.relative_to(root)}"
    assert hooks_path.is_file(), f"missing {hooks_path.relative_to(root)}"

    manifest = json.loads(manifest_path.read_text())
    assert manifest["name"] == mode
    # 版號本身由各 plugin.json 維護、隨每次功能變更調整；此測試只驗證格式與註冊
    # 契約，不寫死特定版號，避免每次版號升級都要同步改測試。
    assert SEMVER_PATTERN.match(manifest["version"]), (mode, manifest["version"])

    registration = json.loads(hooks_path.read_text())
    commands = [
        hook["command"]
        for groups in registration["hooks"].values()
        for group in groups
        for hook in group["hooks"]
    ]
    assert commands, f"no hook commands registered for {mode}"
    # 跨平台命令：依序探測 python3 / python / py，取第一個可執行者
    prefix = (
        'for interpreter in python3 python py; do "$interpreter" -V >/dev/null 2>&1 '
        '&& exec env PYTHONUTF8=1 "$interpreter" "${CLAUDE_PLUGIN_ROOT}/hooks/'
    )
    # 找不到任一直譯器時的清楚錯誤訊息（純附加、不影響 exit code 語意）
    suffix = (
        "\"; done; echo 'ai-guardrail-kit: 找不到可用的 "
        "python3/python/py 直譯器，請安裝 Python 3.9+ "
        "並確認已加入 PATH，安裝完成後"
        "開新的終端機／session 再試一次。"
        "' >&2; exit 127"
    )
    for command in commands:
        assert command.startswith(prefix), f"non-plugin-root command: {command}"
        match = re.fullmatch(
            re.escape(prefix) + r'([^"/]+\.py)' + re.escape(suffix), command
        )
        assert match, f"unexpected hook command: {command}"
        executable = plugin_root / "hooks" / match.group(1)
        assert executable.is_file(), f"missing executable {executable.relative_to(root)}"

    for runtime_file in plugin_root.rglob("*"):
        if runtime_file.is_file():
            contents = runtime_file.read_bytes()
            for legacy_path in (b"$CLAUDE_PROJECT_DIR/.claude/hooks/", b"python3 .claude/hooks/"):
                assert legacy_path not in contents, (
                    f"checkout-dependent hook path in {runtime_file.relative_to(root)}"
                )

approval_command = 'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/approve_plan.py"'
integrated_root = root / "claude/plugins/integrated-harness"
assert approval_command in (integrated_root / "orchestration-policy.md").read_text()
assert approval_command in (integrated_root / "hooks/plan_gate.py").read_text()

guide_path = root / "docs/claude-marketplace.md"
assert guide_path.is_file(), f"missing {guide_path.relative_to(root)}"
guide = guide_path.read_text()
readme = (root / "README.md").read_text()
assert "docs/claude-marketplace.md" in readme, "README does not link Claude marketplace guide"
required_documentation = {
    'claude plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --scope project --sparse .claude-plugin claude/plugins': "remote marketplace registration",
    'claude plugin marketplace add "$(pwd)" --scope project': "marketplace registration",
    "./scripts/select-claude-mode decomposition-gate --scope project .": "decomposition selection",
    "./scripts/select-claude-mode harness --scope project .": "harness selection",
    "./scripts/select-claude-mode integrated-harness --scope project .": "integrated selection",
    "./scripts/select-claude-mode decomposition-gate --scope local .": "local selection",
    "./scripts/verify-claude-mode decomposition-gate .": "verification",
    "./scripts/select-claude-mode --remove --scope project .": "removal",
}
for text, purpose in required_documentation.items():
    assert text in guide, f"missing {purpose}: {text}"
coupled_requirements = {
    r"Selecting the same mode at the same scope is the update workflow": "same-mode update semantics",
    r"Start a new Claude Code session after every successful selection, update, or\s+removal": "lifecycle session restart",
    r"existing top-level `decomposition-gate/`,\s+`harness/`, and `integrated-harness/` copy-in distributions remain supported": "specific copy-in compatibility",
    r"`user`-scope\s+installation is unsupported and the selector and verifier reject it as a\s+conflict": "unsupported user-scope behavior",
    r"direct native commands such as `claude plugin install`,\s+`uninstall`, `enable`, or `disable` bypass selector mutual exclusion": "specific native CLI bypass",
}
for pattern, purpose in coupled_requirements.items():
    assert re.search(pattern, guide), f"missing coupled requirement: {purpose}"

print("PASS: Claude marketplace packages are complete")
PY
