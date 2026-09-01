---
name: integrated-harness
description: Combine decomposition, approval, scope, command, and secret guardrails.
---

# Integrated Harness

This workflow combines decomposition with native Codex `ask`, strict/light scope
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

Deterministic denials do not become approvable. Light mode may allow a provably
scoped `apply_patch`, while a mutating `exec_command` still asks. Obtain explicit
human authorization before production or shared-infrastructure changes,
destructive operations, sensitive-data handling, paid resources, deployment,
pull requests, or outbound communication unless the approved plan already lists
the exact action. Report unrun validation and remaining risk. Plugin hooks are not
a sandbox, and installation alone does not activate them.

Activate it with `$CODEX_HOME/guardrail/bin/select-codex-mode integrated-harness <project-dir>`, verify it with `$CODEX_HOME/guardrail/bin/verify-codex-mode integrated-harness <project-dir>`, then start a new thread after switching. The `./scripts/...` equivalents are only for a local checkout.
