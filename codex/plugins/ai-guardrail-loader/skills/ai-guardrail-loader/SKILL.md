---
name: ai-guardrail-loader
description: Stable Codex loader for project-selected runtimes.
---

# AI Guardrail Loader

The loader is the user's installed entry point for every selectable mode. When
`decomposition-gate` or `integrated-harness` is active, create
`.guardrail/plan/decomposition.md` before implementation. Write task-specific
content using this structure:

```md
# 任務拆解：<任務名稱>

## 問題與目標
<重述要求及完成條件>

## 已知資訊
- <已確認事實>

## 缺少的資訊
- <會影響結果、尚未確認的資訊；沒有就寫「無」>

## 假設
- 【假設】<本次工作依賴的假設>

## 做法與驗證
- <預定修改及驗證方式>

## 允許修改範圍
- `<專案相對路徑>` — <修改原因>
```

Keep facts separate from assumptions and list only task-required paths inside
the project root. Both modes require `## 已知資訊`, `## 缺少的資訊`, and at
least one `【假設】`. Integrated-harness also enforces
`## 允許修改範圍`; decomposition-gate records that scope for clarity but does
not enforce it. Decomposition-gate has no human approval step.

When a hook says that human approval is required, show the user complete,
copy-ready preview and confirm commands. Fill in the actual Python manager
absolute path, project absolute path, cwd, and the current command, patch, or
event file. Never show only the operation SHA-256, a relative path, a
placeholder, or only say that approval is needed. Only the human may run the
approval command in their own terminal; the AI must not run it or request write
access to the approval store.

The loader is the only globally installed Codex plugin from this marketplace.
After bootstrap, modes are selected with
`$CODEX_HOME/guardrail/bin/select-codex-mode` and verified with
`$CODEX_HOME/guardrail/bin/verify-codex-mode`; mode switching never adds or
removes a legacy mode plugin. The hook process is offline and executes only a
verified content-addressed runtime cache entry.

The selector syntax accepts an optional `[project-dir]`. Provide it for
`project` or `local` scope; for `user` scope, omit it to use the current
directory as command context while writing the global user fallback. Start a
new thread after switching modes.

To remove the whole guardrail installation, use the global one-click command.
Without `--confirm` it only lists managed selectors; `--prune-cache` is opt-in
and removes only unreferenced runtime cache entries. Personal policy and
unrelated hooks are preserved.

```bash
guardrail_bin="${CODEX_HOME:-$HOME/.codex}/guardrail/bin"
"$guardrail_bin/uninstall-codex-guardrail"
"$guardrail_bin/uninstall-codex-guardrail" --confirm --prune-cache
```

On Windows PowerShell, invoke `$CODEX_HOME/guardrail/bin/codex-runtime-manager.py`
with `uninstall` (and then `--confirm`) using `py -3` or Python 3.9+.
