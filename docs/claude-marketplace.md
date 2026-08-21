# Claude guardrail marketplace

The Claude marketplace manifest is at `.claude-plugin/marketplace.json`, with
four complete plugins under `claude/plugins/` named `decomposition-gate`,
`sensitive-data-guard`, `harness`, and `integrated-harness`. Use the repository selector to keep
exactly one managed mode effective across the supported `project`, `local`, and `user` scopes.
The selector validates a local checkout as its package source; a separate native Claude CLI
user-scope path is also documented below for remote installation without the selector.

`sensitive-data-guard` is the standalone data-protection option. It blocks
plaintext secrets and prompt PII, and redacts supported PII from write content.
It does not add decomposition, dangerous-command checks, human approval, or
orchestration.

`harness` no longer promotes generation of an orchestration prompt; its legacy
prompt remains deprecated for compatibility. `integrated-harness` uses a slim
governance policy for authorization, side effects, validation, cost, and failure
disclosure. Claude decides ordinary decomposition, model selection, and agent
delegation through its native capabilities.

## Register and select

Register the GitHub marketplace remotely:

```bash
claude plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --scope project --sparse .claude-plugin claude/plugins
```

`--sparse .claude-plugin claude/plugins` limits the checkout to the
marketplace manifest and the plugin packages. The selector below still
requires a local checkout of this repository registered as the marketplace
source; it rejects a git- or github-sourced registration because it validates
the local package content, which cannot be tied to a remote cache. From this
repository root, register the marketplace and select a mode for the current
project:

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

For a user-scope installation managed by this repository, register the local
checkout at `user` scope and select the mode with the same scope:

```bash
claude plugin marketplace add "$(pwd)" --scope user
./scripts/select-claude-mode integrated-harness --scope user .
./scripts/verify-claude-mode integrated-harness .
```

The user scope applies to every Claude Code project for that user. The selector
still owns the mutual-exclusion and rollback boundary across all three scopes.

## Global user-scope installation (native Claude CLI)

To run one managed mode in every Claude Code project, install it through the
native CLI at `user` scope:

```bash
claude plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --scope user --sparse .claude-plugin claude/plugins
claude plugin install integrated-harness@ai-guardrail-kit --scope user
claude plugin list --json
```

Replace `integrated-harness` with one of the four modes. Confirm that the
selected plugin reports `scope` as `user` and `enabled` as `true`. This path
does not use `scripts/select-claude-mode` or `scripts/verify-claude-mode`: the
native commands bypass the selector's package source validation,
mutual-exclusion, and rollback boundary. Keep exactly one managed mode at user
scope and do not combine it with a selector-managed mode.

Remove a native user-scope installation with the native CLI, then start a new
Claude Code session:

```bash
claude plugin uninstall integrated-harness@ai-guardrail-kit --scope user
```

The repository selector's remove command clears all managed modes it finds
across the supported `project`, `local`, and `user` scopes; its `--scope`
argument is validated CLI syntax but does not limit that cleanup to one scope.

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

Policy resolution order for `integrated-harness`: the project
`.claude/orchestration-policy.md` always wins; only when it does not exist is
the personal-level `~/.claude/orchestration-policy.md` consulted. A permissive
personal policy (`standard`/`light`) loosens every project without its own
policy file, so keep per-project policies for high-risk work. With neither
file present, the gate fails closed to `strict`.

These hooks are defense layers, not a security sandbox. Command and secret
detection cannot prove the absence of obfuscation, indirect effects, or every
credential format. Combine them with Claude Code permissions, isolation, secret
management, static analysis, and human review.
