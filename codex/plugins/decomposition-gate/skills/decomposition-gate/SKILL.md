---
name: decomposition-gate
description: Require a valid decomposition artifact before implementation work proceeds.
---

# Decomposition Gate

This workflow gates implementation on `.codex/guardrail/plan/decomposition.md`.
It is workflow discipline, not authorization or a sandbox. Installation alone
does not activate plugin hooks.

Activate it with `$CODEX_HOME/guardrail/bin/select-codex-mode decomposition-gate [--scope project|local|user] [project-dir]`, then verify it with `$CODEX_HOME/guardrail/bin/verify-codex-mode decomposition-gate [--scope project|local|user] [project-dir]`. For `user` scope, omit `[project-dir]` to use the global user fallback; provide it for `project` or `local` scope. Start a new thread after switching. The `./scripts/...` equivalents are only for a local checkout.
