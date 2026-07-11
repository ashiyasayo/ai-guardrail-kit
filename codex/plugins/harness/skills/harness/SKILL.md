---
name: harness
description: Require plan approval and apply command and secret guardrails.
---

# Harness

This workflow returns native Codex `ask` for guarded writes. Permanent command
and credential denials remain independent of approval and cannot be overridden by
it. If host approvals are disabled, the plugin cannot manufacture an equivalent.
Plugin hooks are not a sandbox, and installation alone does not activate them.

Activate it from the repository with `scripts/select-codex-mode harness <project-dir>`, verify it with `scripts/verify-codex-mode harness <project-dir>`, then start a new thread after switching.
