# Integrated Harness Policy

`orchestration-policy.md` controls how the Codex `integrated-harness` plugin
handles writes after its deterministic guardrails have passed. It does not
override the permanent dangerous-command or plaintext-secret denials.

## Policy Location

Create a project policy at:

```text
.codex/guardrail/orchestration-policy.md
```

The project policy takes precedence. When it is absent, the plugin reads the
personal policy at:

```text
~/.codex/guardrail/orchestration-policy.md
```

If neither file can be read, the plugin fails closed to `strict` mode with an
empty Bash allowlist. Use a project policy for repositories that need a
different policy from your personal default.

Selecting `integrated-harness` with `scripts/select-codex-mode` installs this
bundled default at the personal path when no personal policy exists. Existing
personal policies are never overwritten or removed by the selector.

## Approval Modes

Set one mode under `## 核准模式`:

```md
- 核准模式：strict
```

| Mode | `apply_patch` | `exec_command` |
| --- | --- | --- |
| `strict` | Requires Codex native `ask` after plan and scope checks pass. | Only commands matching the strict allowlist are eligible, then require native `ask`. |
| `standard` | Requires Codex native `ask` after plan and scope checks pass. | Requires Codex native `ask` after plan and scope checks pass. |
| `light` | A patch within the approved scope proceeds without `ask`. | Requires Codex native `ask` after plan and scope checks pass. |

Missing or invalid mode values are treated as `strict`.

## Strict Bash Allowlist

In `strict` mode, only commands beginning with an entry under `## Strict Bash
測試與建置 Allowlist` can reach Codex approval. For example:

```md
## Strict Bash 測試與建置 Allowlist

- `bash tests/`
- `dotnet test`
- `dotnet build`
- `npm test`
```

The allowlist is not a shell permission grant. Commands containing shell
operators, redirections, command substitutions, or glob metacharacters are
rejected before approval. Keep entries narrow and project-specific.

## Related Guardrails

Before any approval decision, `integrated-harness` requires a valid
`.codex/guardrail/plan/decomposition.md` with the required sections and an
explicit allowed-modification scope. It also rejects edits to the plan and
policy files themselves. Start a new Codex thread after installing, switching,
or refreshing the plugin so its hooks and skills are reloaded.
