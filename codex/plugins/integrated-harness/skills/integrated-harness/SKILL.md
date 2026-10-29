---
name: integrated-harness
description: Combine decomposition, approval, scope, command, and secret guardrails.
---

# Integrated Harness

This workflow combines decomposition with human-terminal operation approval, strict/light scope
policy, and permanent command and credential checks. Treat the bundled policy as
a governance boundary, not instructions for how to reason, route models, or
orchestrate agents. Platform-native planning and delegation remain available but
must not bypass authorization, external-side-effect, validation, cost, or failure
disclosure requirements.

Keep user-facing progress concise: update only for important findings, blockers,
or direction changes, and lead the final response with the outcome. Delegate only
work that is sizeable, genuinely independent, and parallelizable. Do not spawn an
agent for a task that takes only a handful of tool calls, or solely to re-check the
primary agent's work. Match validation depth to risk and observable impact; do not
repeat checks without new evidence.

Route ambiguous, public-contract, or three-plus-module design work through the
loader-provided `brainstorming` skill. Route complex failures, concurrency issues, or a
failed first fix through `systematic-debugging`. Before writing production code for
a new feature, bug fix, or test-observable behavior change, use
`test-driven-development`; skip it for pure configuration, documentation, or
generated code. Ordinary single-file work and
fully specified fixes should proceed directly. Planning must not contain a full
implementation, and skill routing never requires a worktree or subagent.

Do not delegate ordinary tasks. Only use `subagent-driven-development` for
high-risk changes involving three or more external dependencies, core payments,
authorization architecture, or comparably risky database migrations or
cross-module refactors with isolated ownership. When that workflow is selected, finish with
the loader-provided `requesting-code-review`: one fresh-context reviewer checks spec
compliance, then a different fresh-context reviewer checks code quality.
Critical and Major findings block workflow completion until fixed and re-reviewed.
This is a skill workflow gate, not a deterministic hook-enforced security gate. This review workflow is not
an excuse to delegate ordinary work, and subagents must not spawn descendants.

Deterministic denials do not become approvable. Light mode may allow a provably
scoped `apply_patch`, while a mutating Bash command still requires an operation receipt. Obtain explicit
human authorization before production or shared-infrastructure changes,
destructive operations, sensitive-data handling, paid resources, deployment,
pull requests, or outbound communication unless the approved plan already lists
the exact action. Report unrun validation and remaining risk. Plugin hooks are not
a sandbox, and installation alone does not activate them.

Activate it with `$CODEX_HOME/guardrail/bin/select-codex-mode integrated-harness [--scope project|local|user] [project-dir]`, then verify it with `$CODEX_HOME/guardrail/bin/verify-codex-mode integrated-harness [--scope project|local|user] [project-dir]`. For `user` scope, omit `[project-dir]` to use the global user fallback; provide it for `project` or `local` scope. Start a new thread after switching. The `./scripts/...` equivalents are only for a local checkout.

Only the human may run `python3 "$CODEX_HOME/guardrail/bin/codex-runtime-manager.py" approve`
in their own terminal. Plan drafts live at `.guardrail/plan/decomposition.md`; create one
before implementation and fill it with task-specific content using this structure:

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

Include the exact required markers `## 已知資訊`, `## 缺少的資訊`, `【假設】`,
and `## 允許修改範圍`. Keep facts separate from assumptions and list only
task-required paths inside the project root. Strict/standard mode permits a
plan-only draft patch before approval; a mixed plan and implementation patch is
not a draft-only patch. Light-mode plans must be created and changed by the human.

For a pending operation, use the hook's current digest to prepare one complete,
copy-ready confirmation command for the human. Put the entire command on one
line and use the actual Python executable, manager absolute path, project
absolute path, exact operation input (`--command`, `--patch-file`, or
`--event-file` as appropriate), and `--confirm` with the current operation digest.
Use `--event-file` when the operation has exact tool-input fields or a subdirectory
cwd. A patch/event file named in the command must already contain the exact
reviewed input. Do not show a preview-plus-confirm pair, placeholders, relative
paths, only a digest, or merely say approval is required.
This receipt authorizes one operation bound to the plan and policy hashes, not
the plan in general. Only the human runs it in their own terminal.
Never execute approval commands for the human, edit the approval store, or request sandbox
access to that store. Missing or invalid receipts deny the operation. Permanent security
denials still apply. Verify wiring with `verify-codex-mode --diagnose` and review `/hooks`.
Policies and emergency bypass files remain protected under `.codex/guardrail/`.
