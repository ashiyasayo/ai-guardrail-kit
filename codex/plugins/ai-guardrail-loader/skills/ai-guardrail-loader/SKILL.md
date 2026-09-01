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
