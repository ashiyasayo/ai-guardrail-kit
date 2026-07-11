# Codex Plugin Marketplace Design

## Goal

Package the three mutually exclusive guardrail modes as complete, Codex-native
plugins distributed from one repository-owned marketplace. Users select exactly
one mode through a single command that installs or updates the target and removes
the other two.

The three modes retain their existing product meanings:

- `decomposition-gate` enforces task decomposition before write operations.
- `harness` enforces human approval and permanent safety checks.
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
marketplaces/
└── codex/
    └── marketplace.json

plugins/
├── decomposition-gate/
│   └── codex/
│       ├── .codex-plugin/plugin.json
│       ├── hooks/
│       ├── skills/
│       └── scripts/
├── harness/
│   └── codex/
└── integrated-harness/
    └── codex/

scripts/
├── select-codex-mode
└── verify-codex-mode

tests/
├── codex_marketplace_test.sh
├── codex_mode_switch_test.sh
└── codex_guardrail_test.sh
```

When the Claude marketplace is implemented, each product may gain a `shared/`
directory for platform-neutral schemas, fixtures, and rule vectors. That later
reorganization must preserve compatibility with the current top-level Claude
installation paths.

## Marketplace and Plugin Packaging

The repository contains one Codex marketplace manifest with exactly three local
plugin entries. Each entry points to one Codex plugin package and includes the
required installation policy, authentication policy, and category metadata.

Each plugin has its own normalized name and semantic version. Its
`.codex-plugin/plugin.json` contains only fields supported by Codex validation.
Hook companion files are packaged separately rather than represented through an
unsupported manifest field. Skills describe the user-visible workflow; hooks
provide deterministic enforcement.

Local development updates use the Codex cachebuster and reinstall flow. The
marketplace file is not hand-edited as part of an update operation. After a mode
change, the command tells the user to start a new thread so newly installed
skills and hooks are loaded cleanly.

## Mutual Exclusion and Mode Selection

Codex marketplace metadata is not treated as a native mutual-exclusion system.
The repository enforces the invariant through `select-codex-mode` and
`verify-codex-mode`.

The selector accepts exactly one of:

```text
decomposition-gate
harness
integrated-harness
```

Its operation is:

1. Validate the requested name and marketplace before changing installed state.
2. Read the installed state of all three managed plugins.
3. Remove the two non-target modes.
4. Install or update the requested mode from the repository marketplace.
5. Run the verifier and require exactly the requested mode to remain.

An invalid mode or marketplace causes no state change. If target installation
fails after another mode was removed, the selector attempts to restore the
previous mode. It exits unsuccessfully and reports whether restoration succeeded;
it never reports a successful switch unless final verification passes.

The verifier supports both human use and CI. It fails when more than one managed
mode is installed. During a completed selection it also checks that the expected
target is the sole installed mode.

Direct use of the Codex plugin CLI can bypass the selector. Documentation must
state this boundary, and each mode must fail closed when it can reliably detect a
conflicting managed mode at runtime. The project does not claim marketplace-level
native exclusion.

## Guardrail Behavior

### Decomposition Gate

The plugin skill requires a structured decomposition artifact before
implementation. Its pre-write hook validates that the artifact exists and
contains the required known-information and missing-information sections plus at
least one explicit assumption marker. Missing or malformed decomposition blocks
write-capable operations.

This mode is workflow discipline, not human authorization or a security sandbox.

### Harness

The plugin blocks write-capable operations without a current human approval
record. Approval is created only by a user-run repository script and expires
after the configured interval. The Codex workflow and hook cannot approve their
own plan.

Independent safety hooks block destructive shell commands and likely plaintext
credentials. These checks are permanent and are not bypassed by plan approval.

### Integrated Harness

The plugin combines decomposition validation, human approval, destructive-command
blocking, credential blocking, and orchestration guidance. In strict mode,
approval records include a SHA-256 digest of the decomposition artifact. Editing
the artifact invalidates the approval. Light mode follows its explicit Codex
policy while retaining permanent command and credential checks.

Codex policy is stored separately from Claude settings. The three Codex plugins
share a Python 3.9 minimum to simplify distribution and testing.

## Error Handling and Security Boundaries

All guardrails fail closed for missing files, malformed input, unreadable policy,
expired approval, digest mismatch, and hook parsing errors. Error messages state
which condition failed and identify the user action needed to proceed without
revealing credential content.

Regex-based command and secret detection remains a defense layer rather than a
complete sandbox. Documentation preserves this limitation and recommends Codex
permissions, secret managers, static analysis, and human review as complementary
controls.

The selector limits its mutations to the three marketplace-managed plugin names.
It does not alter unrelated plugins or Codex configuration.

## Testing

Implementation follows test-first development. Automated tests cover:

- all three plugin manifests and the marketplace schema;
- exactly three correctly named marketplace entries;
- no state mutation for an invalid mode;
- all six transitions between distinct modes;
- idempotent selection of the already active mode;
- restoration reporting after simulated installation failure;
- conflict detection when two or more modes appear installed;
- decomposition rejection for missing and malformed artifacts and acceptance of a
  valid artifact;
- approval rejection when absent or expired and acceptance when valid;
- permanent blocking of representative destructive commands and plaintext
  credentials;
- integrated approval invalidation after decomposition content changes;
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
3. The selector safely switches among all modes and final state always satisfies
   mutual exclusion after a reported success.
4. Guardrail and switching regression tests pass in isolation.
5. Existing Claude tests remain unchanged and pass.
6. Installation, selection, update, verification, limitations, and new-thread
   activation are documented.
