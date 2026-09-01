---
name: decomposition-gate
description: Require a valid decomposition artifact before implementation work proceeds.
---

# Decomposition Gate

This workflow gates implementation on `.codex/guardrail/plan/decomposition.md`.
It is workflow discipline, not authorization or a sandbox. Installation alone
does not activate plugin hooks.

Activate it with `$CODEX_HOME/guardrail/bin/select-codex-mode decomposition-gate <project-dir>`, verify it with `$CODEX_HOME/guardrail/bin/verify-codex-mode decomposition-gate <project-dir>`, then start a new thread after switching. The `./scripts/...` equivalents are only for a local checkout.
