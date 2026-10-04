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

Selecting `integrated-harness` with
`$CODEX_HOME/guardrail/bin/select-codex-mode` installs this bundled default at
the personal path when no personal policy exists. Existing personal policies
are never overwritten or removed by the selector. The `./scripts/...` equivalent
is only for a local checkout.

## Approval Modes

Set one mode under `## 核准模式`:

```md
- Approval Mode: strict
```

| Mode | `apply_patch` | `exec_command` |
| --- | --- | --- |
| `strict` | Requires a human-terminal operation receipt after plan and scope checks pass. | Only commands matching the strict allowlist are eligible, then require a human-terminal operation receipt. |
| `standard` | Requires a human-terminal operation receipt after plan and scope checks pass. | Requires a human-terminal operation receipt after plan and scope checks pass. |
| `light` | A patch within the approved scope proceeds without an operation receipt. | Requires a human-terminal operation receipt after plan and scope checks pass. |

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
`.guardrail/plan/decomposition.md` with the required sections and an
explicit allowed-modification scope. A strict/standard patch may edit only the plan draft; light-mode plans and all policy files
remain human-managed. Start a new Codex thread after installing, switching,
or refreshing the plugin so its hooks and skills are reloaded.

Each entry under `## 允許修改範圍` may include a same-line description after
a backtick-delimited path, for example ``- `src/app.py` — application code``.
When a description is present, the path must be enclosed in backticks. An
unquoted entry continues to treat the whole line as the path for compatibility.

See [approval commands, migration and diagnostics](../../../docs/codex-hook-compatibility.md).
