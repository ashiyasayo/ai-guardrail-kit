---
name: ai-guardrail-loader
description: Stable Codex loader for project-selected runtimes.
---

# AI Guardrail Loader

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
