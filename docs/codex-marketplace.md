# Codex guardrail marketplace

The Codex implementation lives under `codex/`: one repository marketplace and
three complete plugins named `decomposition-gate`, `harness`, and
`integrated-harness`. Select exactly one. These plugins implement the same product
intent as the top-level Claude packages, but Codex hook, approval, installation,
and policy semantics are platform-specific and are not claimed to be identical.

## Requirements and first installation

Use Codex and Python 3.9 or newer. From this repository root, configure the local
marketplace and select a mode for a project:

```bash
codex plugin marketplace add "$(pwd)/codex"
./scripts/select-codex-mode decomposition-gate .
./scripts/verify-codex-mode decomposition-gate .
```

Substitute `harness` or `integrated-harness` in both repository commands. Use an
explicit project directory instead of `.` when configuring another project.
Selection installs the target, removes the other two managed plugins, writes the
selector-owned hook block in the project's `.codex/config.toml`, and verifies that
the installed plugin and active hooks agree. Marketplace metadata itself does not
provide mutual exclusion, and plugin installation alone does not activate hooks.

After every selection or reinstall, start a new thread. Existing threads do not
reliably reload newly installed skills and hooks.

## Choosing a mode

- `decomposition-gate` requires `.codex/guardrail/plan/decomposition.md` before
  writes. It is workflow discipline, not human authorization or a sandbox.
- `harness` returns native Codex `ask` for guarded writes after deterministic
  safety checks.
- `integrated-harness` adds decomposition, policy, scope, and audit context. Strict
  mode asks after all deterministic checks pass. Light mode may allow a provably
  scoped `apply_patch`, but mutating `exec_command` still asks.

Native `ask` delegates the approval prompt to Codex; no approval file, nonce, or
repository command substitutes for a human response. If approvals are disabled
by the Codex host or execution policy, these plugins cannot turn them back on or
provide equivalent authorization. Destructive-command and plaintext-credential
denials are deterministic and independent of approval eligibility: approval does
not override them, in strict or light mode.

## Managed state and verification

The selector exclusively owns the text from
`# ai-guardrail-kit:begin` through `# ai-guardrail-kit:end` in
`.codex/config.toml`. Do not edit that block. Content outside it is preserved.
The selector rejects malformed delimiters, symlinks, and non-regular config
targets. Run the verifier after any suspected state change:

```bash
./scripts/verify-codex-mode integrated-harness /path/to/project
```

Direct `codex plugin add/remove` can desynchronize installed plugin state from
the project hook block. Use the selector for installation, switching, refreshing,
and safe removal:

```bash
./scripts/select-codex-mode --remove /path/to/project
./scripts/verify-codex-mode --no-managed-mode /path/to/project
```

Removal transactionally removes all managed plugins and only the selector-owned
config block. Unrelated plugins and config bytes are preserved. Repeating it is
safe.

## Local update workflow

Codex caches installed local plugin content. During repository development,
refresh the selected plugin transactionally through the selector:

```bash
./scripts/select-codex-mode <mode> .
./scripts/verify-codex-mode <mode> .
```

The selector removes and re-adds an already selected target, so the same command
refreshes cached plugin content with transactional rollback. Start a new thread
afterward.

## Failure, rollback, and security boundaries

Before mutation, the selector snapshots managed plugin state and the project
config. A post-mutation error reports either `rollback succeeded` or `rollback
also failed`; neither message means the requested switch succeeded. Inspect the
reported state and rerun the verifier before continuing.

Atomic rename protects each config replacement, but validation and snapshotting
cannot be atomic across an externally mutable project path. A TOCTOU window
remains if another process changes the config between those operations. Rollback
is best-effort and also depends on the Codex plugin CLI and filesystem remaining
available. Avoid concurrent config/plugin changes and keep version-control or
another external backup for recovery.

Hooks are defense layers, not a security sandbox. Regex command/secret detection
cannot prove the absence of obfuscation, indirect effects, or every credential
format. Light-mode scope checks only bypass a prompt for deterministic
`apply_patch` paths; arbitrary shell effects are not treated as scoped. Combine
these controls with Codex permissions, isolation, secret management, static
analysis, and human review.
