---
name: integrated-harness
description: Combine decomposition, approval, scope, command, and secret guardrails.
---

# Integrated Harness

This workflow combines decomposition with native Codex `ask`, strict/light scope
policy, and permanent command and credential checks. Deterministic denials do not
become approvable. Light mode may allow a provably scoped `apply_patch`, while a
mutating `exec_command` still asks. Plugin hooks are not a sandbox, and
installation alone does not activate them.

Activate it from the repository with `scripts/select-codex-mode integrated-harness <project-dir>`, verify it with `scripts/verify-codex-mode integrated-harness <project-dir>`, then start a new thread after switching.
