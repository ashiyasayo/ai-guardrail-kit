---
name: harness
description: Require plan approval and apply command and secret guardrails.
---

# Harness

This workflow returns native Codex `ask` for guarded writes. Permanent command
and credential denials remain independent of approval and cannot be overridden by
it. If host approvals are disabled, the plugin cannot manufacture an equivalent.
Plugin hooks are not a sandbox, and installation alone does not activate them.

Activate it with `$CODEX_HOME/guardrail/bin/select-codex-mode harness [--scope project|local|user] [project-dir]`, then verify it with `$CODEX_HOME/guardrail/bin/verify-codex-mode harness [--scope project|local|user] [project-dir]`. For `user` scope, omit `[project-dir]` to use the global user fallback; provide it for `project` or `local` scope. Start a new thread after switching. The `./scripts/...` equivalents are only for a local checkout.
