#!/usr/bin/env bash
set -euo pipefail
# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

require() {
  local file="$1" pattern="$2" label="$3"
  if grep -q "$pattern" "$file"; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s\n' "$label"
    fail=$((fail + 1))
  fi
}

for section in A B C D E F G H I; do
  require "$ROOT/ORCHESTRATOR.md" "## $section\." "ORCHESTRATOR 包含 $section 章"
done
if python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
settings = json.loads((root / ".claude/settings.json").read_text(encoding="utf-8"))
groups = settings["hooks"]["PreToolUse"]

# 單一進入點契約：只註冊 guard.py 一條規則，三道檢查在 guard 內依序執行
assert len(groups) == 1, groups
assert groups[0]["matcher"] == "*"
commands = [hook["command"] for hook in groups[0]["hooks"]]
assert len(commands) == 1 and "guard.py" in commands[0], commands
for script in ("guard.py", "plan_gate.py", "block_secrets.py", "block_dangerous_commands.py"):
    assert (root / ".claude/hooks" / script).is_file()
PY
then
  printf 'PASS: settings hook 契約\n'
else
  printf 'FAIL: settings hook 契約\n'
  fail=$((fail + 1))
fi

if PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT" <<'PY'
import importlib.util
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
path = root / ".claude/hooks/plan_gate.py"
spec = importlib.util.spec_from_file_location("plan_gate", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.APPROVAL_MODES == {"strict", "standard", "light"}
template = (root / ".claude/plan/decomposition.template.md").read_text(encoding="utf-8")
assert module.SCOPE_HEADER in template
PY
then
  printf 'PASS: 模式與拆解範本契約\n'
else
  printf 'FAIL: 模式與拆解範本契約\n'
  fail=$((fail + 1))
fi

if python3 - "$ROOT" <<'PY'
import ast
import pathlib
import sys

hooks = pathlib.Path(sys.argv[1]) / ".claude/hooks"
violations = []
for path in hooks.glob("*.py"):
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    annotations = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            annotations.extend(
                arg.annotation for arg in node.args.posonlyargs + node.args.args if arg.annotation
            )
            annotations.extend(arg.annotation for arg in node.args.kwonlyargs if arg.annotation)
            if node.args.vararg and node.args.vararg.annotation:
                annotations.append(node.args.vararg.annotation)
            if node.args.kwarg and node.args.kwarg.annotation:
                annotations.append(node.args.kwarg.annotation)
            if node.returns:
                annotations.append(node.returns)
        elif isinstance(node, ast.AnnAssign):
            annotations.append(node.annotation)
    if any(
        isinstance(part, ast.BinOp) and isinstance(part.op, ast.BitOr)
        for annotation in annotations
        for part in ast.walk(annotation)
    ):
        violations.append(path.name)
assert not violations, f"hook annotations 使用 PEP 604 union：{', '.join(violations)}"
PY
then
  printf 'PASS: hook annotation 相容 Python 3.9\n'
else
  printf 'FAIL: hook annotation 相容 Python 3.9\n'
  fail=$((fail + 1))
fi

if python3 - "$ROOT" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
claude = (root / "CLAUDE.md").read_text(encoding="utf-8")
readme = (root / "README.md").read_text(encoding="utf-8")
policy = (root / ".claude/orchestration-policy.md").read_text(encoding="utf-8")
for required in ("ORCHESTRATOR.md", ".claude/reasoning-protocol-subagent.md"):
    assert required in claude
install_heading = "## 安裝"
assert install_heading in readme
install_section = readme.split(install_heading, 1)[1].split("\n## ", 1)[0]
for install_item in (".claude/", "CLAUDE.md", "ORCHESTRATOR.md"):
    assert install_item in install_section
assert "## Strict Bash 測試與建置 Allowlist" in policy
PY
then
  printf 'PASS: 入口與安裝結構契約\n'
else
  printf 'FAIL: 入口與安裝結構契約\n'
  fail=$((fail + 1))
fi

for mode in strict standard light; do
  require "$ROOT/README.md" "\`$mode\`" "README 說明 $mode 模式"
  require "$ROOT/.claude/orchestration-policy.md" "核准模式：$mode\|\`$mode\`" "政策說明 $mode 模式"
done
require "$ROOT/README.md" 'Python 3\.9+' 'README 說明 Python 3.9+ 需求'

printf '結果：%d 失敗\n' "$fail"
test "$fail" -eq 0
