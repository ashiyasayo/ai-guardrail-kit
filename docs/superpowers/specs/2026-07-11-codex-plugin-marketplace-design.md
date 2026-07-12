# Codex Plugin Marketplace Design

## Goal

Package the three mutually exclusive guardrail modes as complete, Codex-native
plugins distributed from one repository-owned marketplace. Users select exactly
one mode through a single command that installs or updates the target and removes
the other two.

The three modes retain their existing product meanings:

- `decomposition-gate` enforces task decomposition before write operations.
- `harness` requests native Codex human approval and enforces permanent safety checks.
- `integrated-harness` combines both controls with orchestration policy.

The initial delivery targets Codex only. Existing Claude Code behavior and file
locations remain unchanged. A later phase may add a Claude marketplace within
this repository and extract genuinely shared rules and test vectors.

## Repository Strategy

Codex and Claude implementations remain in one repository. Platform-specific
manifests, hooks, skills, and scripts are isolated so that platform lifecycle
differences do not leak across implementations. Shared security semantics stay
close enough to review and test together.

The first phase adds new Codex paths without moving the current Claude assets:

```text
codex/
├── marketplace.json
└── plugins/
    ├── decomposition-gate/
    │   ├── .codex-plugin/plugin.json
    │   ├── hooks/
    │   ├── skills/
    │   └── scripts/
    ├── harness/
    └── integrated-harness/

scripts/
├── select-codex-mode
└── verify-codex-mode

.codex/
└── config.toml                 # selector-managed project hook activation

tests/
├── codex_marketplace_test.sh
├── codex_mode_switch_test.sh
└── codex_guardrail_test.sh
```

When the Claude marketplace is implemented it will use the parallel
`claude/plugins/<mode>` layout. Platform-neutral schemas, fixtures, and rule
vectors may live under repository-root `shared/`. That later reorganization must
preserve compatibility with the current top-level Claude installation paths.

## Marketplace and Plugin Packaging

The repository contains one Codex marketplace manifest with exactly three local
plugin entries. Each entry points to one Codex plugin package and includes the
required installation policy, authentication policy, and category metadata.

Each plugin has its own normalized name and semantic version. Its
`.codex-plugin/plugin.json` contains only fields supported by Codex validation.
Skills describe the user-visible workflow; hook executables provide deterministic
enforcement.

Codex currently exposes stable hooks but does not expose plugin-installed hooks as
an active plugin capability (`plugin_hooks` is removed). Installing a plugin alone
therefore cannot activate its hook executables. The selector installs the plugin
content and manages a clearly delimited hook block in the target project's
`.codex/config.toml`. This project configuration references the selected plugin's
hook executables. The selector preserves all configuration outside its managed
block.

Local development updates use the Codex cachebuster and reinstall flow. The
marketplace file is not hand-edited as part of an update operation. After a mode
change, the command tells the user to start a new thread so newly installed
skills and hooks are loaded cleanly.

## Mutual Exclusion and Mode Selection

Codex marketplace metadata is not treated as a native mutual-exclusion system,
and plugin installation does not activate plugin hooks. The repository enforces
the invariant through `select-codex-mode`, `verify-codex-mode`, and the selector-
managed project hook configuration.

The selector accepts exactly one of:

```text
decomposition-gate
harness
integrated-harness
```

Its operation is:

1. Validate the requested name and marketplace before changing installed state.
2. Validate that the project's `.codex/config.toml` can be read and updated while
   preserving configuration outside the managed hook block.
3. Read the installed state of all three managed plugins and save the current
   managed hook block for rollback.
4. Remove the two non-target modes.
5. Install or update the requested mode from the repository marketplace.
6. Atomically replace the managed hook block with the target mode's hooks.
7. Run the verifier and require exactly the requested plugin and hook set to
   remain.

An invalid mode, marketplace, or uneditable project configuration causes no state
change. Distinct-mode switches and removal are transactional. If target
installation or hook activation fails after another mode was
removed, the selector attempts to restore both the previous plugin and the
previous managed hook block. Configuration writes use a temporary sibling file
and atomic rename. The selector exits unsuccessfully and reports whether
restoration succeeded; it never reports a successful switch unless final
verification passes.

Same-mode refresh does not remove the target or rewrite configuration. It first
prevalidates the exact installed state, exact managed block, repository hook
paths, and executable sources. A mismatch fails without mutation and directs the
user to perform a normal switch repair. The official `codex plugin add
<target>@ai-guardrail-kit` is then the final irreversible commit point. Per the
CLI contract, add failure preserves the old installed content. Once add succeeds,
the selector cannot restore the prior cached generation: a failed post-check is
reported as `update applied but verification failed`, with no rollback claim.

The verifier supports both human use and CI. It fails when more than one managed
mode is installed, when the managed hook block does not match the installed mode,
or when one side is absent. During a completed selection it checks that the
expected target is both the sole installed plugin and the sole active managed
hook set.

Direct use of the Codex plugin CLI can bypass the selector and `codex plugin
remove` does not clean the project hook block. Documentation must state this
boundary and direct installation, switching, and removal through the repository
commands. The project does not claim marketplace-level native exclusion or
plugin-managed hook activation.

## Guardrail Behavior

### Decomposition Gate

The plugin skill requires a structured decomposition artifact before
implementation. Its pre-write hook validates that the artifact exists and
contains the required known-information and missing-information sections plus at
least one explicit assumption marker. Missing or malformed decomposition blocks
write-capable operations.

This mode is workflow discipline, not human authorization or a security sandbox.

### Harness

For write-capable operations, the plugin returns the native Codex `ask` decision
so the Codex UI or CLI obtains approval from the human. It does not use a
repository-local approval file or approval script because an agent could invoke
such a script through a tool. Read-only operations continue normally.

Independent safety hooks block destructive shell commands and likely plaintext
credentials. These checks are permanent and are not bypassed by plan approval.

### Integrated Harness

The plugin combines decomposition validation, native human approval,
destructive-command blocking, credential blocking, and orchestration guidance.
In strict mode, the hook computes the current decomposition SHA-256 for audit
context and returns `ask` only after the plan, scope, and strict allowlist checks
pass. Because each approval is tied to the current tool request, editing the plan
causes later requests to be checked against the new content. Light mode permits
only deterministically scoped `apply_patch` requests without an approval prompt.
Mutating `exec_command` requests still return native `ask`, because arbitrary
shell filesystem effects cannot be proven to stay within the declared scope.
Permanent command and credential checks remain active in every mode.

Codex policy is stored separately from Claude settings. The three Codex plugins
share a Python 3.9 minimum to simplify distribution and testing.

## Error Handling and Security Boundaries

All guardrails fail closed for missing files, malformed input, unreadable policy,
invalid scope, and hook parsing errors. Error messages state
which condition failed and identify the user action needed to proceed without
revealing credential content.

Regex-based command and secret detection remains a defense layer rather than a
complete sandbox. Documentation preserves this limitation and recommends Codex
permissions, secret managers, static analysis, and human review as complementary
controls.

The selector limits plugin mutations to the three marketplace-managed names. It
alters only its delimited block in project `.codex/config.toml`; unrelated plugins
and configuration are preserved byte-for-byte. Symlinked or non-regular config
targets are rejected unless a later design explicitly defines safe handling.

## Testing

Implementation follows test-first development. Automated tests cover:

- all three plugin manifests and the marketplace schema;
- exactly three correctly named marketplace entries;
- no state mutation for an invalid mode;
- all six transitions between distinct modes;
- same-mode refresh generation advance, failed-add generation preservation, and
  honest post-commit verification failure reporting;
- restoration reporting after simulated installation failure;
- atomic rollback after simulated hook-configuration failure;
- conflict detection when two or more modes appear installed;
- mismatch detection between installed mode and active managed hooks;
- preservation of unrelated `.codex/config.toml` content;
- decomposition rejection for missing and malformed artifacts and acceptance of a
  valid artifact;
- native `ask` output for guarded writes and no repository-local approval bypass;
- permanent blocking of representative destructive commands and plaintext
  credentials;
- integrated `ask` audit context changes after decomposition content changes;
- strict and light policy behavior;
- continued success of the existing Claude smoke and orchestration tests.

Command-line tests use an isolated fake Codex executable and temporary state so
they never mutate the developer's installed plugins. Plugin validation uses the
official local validator before delivery.

## Success Criteria

The Codex phase is complete when:

1. The repository marketplace validates and exposes all three plugins.
2. Each plugin contains Codex-native workflow and enforcement behavior matching
   its documented product scope.
3. The selector safely switches among all modes and final plugin plus project-hook
   state always satisfies mutual exclusion after a reported success.
4. Guardrail and switching regression tests pass in isolation.
5. Existing Claude tests remain unchanged and pass.
6. Installation, selection, update, verification, native approval semantics,
   limitations, and new-thread activation are documented.
