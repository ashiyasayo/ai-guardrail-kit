# Claude guardrail marketplace

The Claude marketplace manifest is at `.claude-plugin/marketplace.json`, with
three complete plugins under `claude/plugins/` named `decomposition-gate`,
`harness`, and `integrated-harness`. Use the repository selector to keep
exactly one managed mode effective across project and local scope.

## Register and select

Register the GitHub marketplace remotely:

```bash
claude plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --scope project --sparse .claude-plugin claude/plugins
```

`--sparse .claude-plugin claude/plugins` limits the checkout to the
marketplace manifest and the plugin packages. The selector below still
requires a local checkout of this repository registered as the marketplace
source; from this repository root, register the marketplace and select a mode
for the current project:

```bash
claude plugin marketplace add "$(pwd)" --scope project
./scripts/select-claude-mode decomposition-gate --scope project .
./scripts/verify-claude-mode decomposition-gate .
./scripts/select-claude-mode --remove --scope project .
```

The selector also accepts either of the other managed modes:

```bash
./scripts/select-claude-mode harness --scope project .
./scripts/select-claude-mode integrated-harness --scope project .
```

Pass another project directory instead of `.` when operating on that project.
For a local-scope installation, register the marketplace at local scope and
select with the same scope:

```bash
claude plugin marketplace add "$(pwd)" --scope local
./scripts/select-claude-mode decomposition-gate --scope local .
```

Only `project` and `local` are supported managed scopes. A `user`-scope
installation is unsupported and the selector and verifier reject it as a
conflict. The remove command clears all managed modes it finds across both
supported scopes; its `--scope` argument is validated CLI syntax but does not
limit that cleanup to one scope.

Start a new Claude Code session after every successful selection, update, or
removal. An existing session does not reliably reload changed plugins and hooks.

## Updates and verification

Selecting the same mode at the same scope is the update workflow:

```bash
./scripts/select-claude-mode decomposition-gate --scope project .
./scripts/verify-claude-mode decomposition-gate .
```

Before updating, the selector verifies that exactly that enabled managed mode is
present. It then runs the native plugin update and verifies again. Once the
native update succeeds, it is committed: a later verification failure is
reported as `update applied but verification failed` and is not claimed to have
been rolled back.

For an explicit no-managed-mode check after removal, run:

```bash
./scripts/verify-claude-mode --no-managed-mode .
```

Use these repository commands for selection, switching, updating, removal, and
verification; direct native commands such as `claude plugin install`,
`uninstall`, `enable`, or `disable` bypass selector mutual exclusion and can
leave conflicting managed modes across scopes.

## Compatibility and security boundary

The marketplace is additive. The existing top-level `decomposition-gate/`,
`harness/`, and `integrated-harness/` copy-in distributions remain supported;
their commands, files, settings, and approval behavior are unchanged. Do not
combine a legacy copy-in mode with a marketplace mode without manually checking
the resulting hooks.

These hooks are defense layers, not a security sandbox. Command and secret
detection cannot prove the absence of obfuscation, indirect effects, or every
credential format. Combine them with Claude Code permissions, isolation, secret
management, static analysis, and human review.
