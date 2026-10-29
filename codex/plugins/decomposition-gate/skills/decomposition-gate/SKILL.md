---
name: decomposition-gate
description: Require a valid decomposition artifact before implementation work proceeds.
---

# Decomposition Gate

This workflow gates implementation on `.guardrail/plan/decomposition.md`.
It is workflow discipline, not authorization or a sandbox. Installation alone
does not activate plugin hooks.

## Write the decomposition document

Before implementation or another project-file write, create
`.guardrail/plan/decomposition.md` at the project root. Write task-specific
content; do not create a file containing only the required headings. Use this
compact structure:

```md
# 任務拆解：<任務名稱>

## 問題與目標
<重述使用者要求及完成條件>

## 已知資訊
- <已由使用者或專案資料確認的事實>

## 缺少的資訊
- <會影響結果、目前尚未確認的資訊；沒有就寫「無」>

## 假設
- 【假設】<本次工作依賴的假設>

## 做法與驗證
- <預定修改及如何確認結果>

## 允許修改範圍
- `<專案相對路徑>` — <修改原因>
```

Keep facts, unknowns, and assumptions distinct. List only task-required paths
inside the project root. The deterministic gate requires the exact markers
`## 已知資訊`, `## 缺少的資訊`, and at least one `【假設】`; useful scope and
verification details help prevent unrelated edits even though this mode does
not enforce an allowed-path list.

This mode has no human approval step. Do not invent an approval command for it.
The integrated-harness mode has a separate one-time operation receipt workflow.

Activate it with `$CODEX_HOME/guardrail/bin/select-codex-mode decomposition-gate [--scope project|local|user] [project-dir]`, then verify it with `$CODEX_HOME/guardrail/bin/verify-codex-mode decomposition-gate [--scope project|local|user] [project-dir]`. For `user` scope, omit `[project-dir]` to use the global user fallback; provide it for `project` or `local` scope. Start a new thread after switching. The `./scripts/...` equivalents are only for a local checkout.
