---
name: harness
description: Require plan approval and apply command and secret guardrails.
---

# Harness

This workflow requires human-terminal operation approval for guarded writes. Permanent command
and credential denials remain independent of approval and cannot be overridden by
it. Receipts expire after 10 minutes, bind the exact operation and context, and are consumed once.
Plugin hooks are not a sandbox, and installation alone does not activate them.

Activate it with `$CODEX_HOME/guardrail/bin/select-codex-mode harness [--scope project|local|user] [project-dir]`, then verify it with `$CODEX_HOME/guardrail/bin/verify-codex-mode harness [--scope project|local|user] [project-dir]`. For `user` scope, omit `[project-dir]` to use the global user fallback; provide it for `project` or `local` scope. Start a new thread after switching. The `./scripts/...` equivalents are only for a local checkout.

Only the human may run `python3 "$CODEX_HOME/guardrail/bin/codex-runtime-manager.py" approve`
in their own terminal. Preview with `--project <project> --command <command>` or
`--patch-file <reviewed.diff>`, then confirm the displayed digest with `--confirm <SHA256>`.
Use `--event-file <reviewed-event.json>` for exact tool input fields or a subdirectory cwd.
When asking for approval, show complete copy-ready preview and confirm commands with the actual
Python manager absolute path, project absolute path, cwd, operation input, and digest. Do not show
placeholders, relative paths, only the digest, or merely say that approval is required.
Never execute approval commands for the human, edit the approval store, or request sandbox
access to that store. Missing or invalid receipts deny the operation. Permanent security
denials still apply. Verify wiring with `verify-codex-mode --diagnose` and review `/hooks`.
