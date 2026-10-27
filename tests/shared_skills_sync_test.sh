#!/usr/bin/env bash
set -euo pipefail

if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
export PYTHONUTF8=${PYTHONUTF8:-1}

repo=$(cd "$(dirname "$0")/.." && pwd -P)
bash "$repo/scripts/sync-shared-skills" --check

# 同步器不得跟隨目標檔或父目錄 symlink 寫出 repository 邊界。
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/shared" "$fixture/outside"
cp -R "$repo/shared/skills" "$fixture/shared/skills"
mkdir -p "$fixture/integrated-harness/.claude" \
  "$fixture/claude/plugins/integrated-harness/skills" \
  "$fixture/codex/plugins/ai-guardrail-loader/skills"
if ln -s "$fixture/outside" "$fixture/integrated-harness/.claude/skills" 2>/dev/null; then
  if AI_GUARDRAIL_ROOT="$fixture" bash "$repo/scripts/sync-shared-skills" >/dev/null 2>&1; then
    printf 'sync-shared-skills followed a symlink parent\n' >&2
    exit 1
  fi
fi

python3 - "$repo" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for name in (
    "brainstorming",
    "systematic-debugging",
    "subagent-driven-development",
    "requesting-code-review",
):
    text = (root / "shared/skills" / name / "SKILL.md").read_text(encoding="utf-8")
    assert "using-superpowers" not in text

brainstorming = (root / "shared/skills/brainstorming/SKILL.md").read_text(encoding="utf-8")
assert "完整實作程式碼" in brainstorming
assert "極小可能" in brainstorming
assert "Git worktree" in brainstorming
assert "跨三個以上模組" in brainstorming.split("---", 2)[1]

debugging = (root / "shared/skills/systematic-debugging/SKILL.md").read_text(encoding="utf-8")
assert "三次停損" in debugging
assert "git checkout" in debugging

subagents = (root / "shared/skills/subagent-driven-development/SKILL.md").read_text(encoding="utf-8")
assert "自動載入 `requesting-code-review`" in subagents
assert "每個 review 階段最多進行兩輪" in subagents
assert "子代理不得派發任何下一層代理" in subagents
assert "輕量、低成本模型" in subagents
assert "Git worktree" in subagents
assert "不構成新的委派理由" in subagents
assert "其他不需高階推理的背景工作" not in subagents

review = (root / "shared/skills/requesting-code-review/SKILL.md").read_text(encoding="utf-8")
assert "Stage 1：Spec Compliance" in review
assert "Stage 2：Code Quality" in review
assert "`Critical`" in review and "`Major`" in review and "`Minor`" in review
assert "SQL 注入" in review and "race condition" in review and "最小修正 diff" in review
assert "明確接受風險" not in review
print("PASS: shared workflow skills are synchronized and decoupled")
PY
