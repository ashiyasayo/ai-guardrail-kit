# Claude Plugin Marketplace Design

## Goal

Add a Claude Code-native marketplace containing the three existing, mutually
exclusive guardrail modes while preserving every current copy-in installation
path. Users install, update, switch, and remove marketplace modes through a
repository selector that guarantees one effective mode across supported scopes.

The managed modes remain:

- `decomposition-gate` for decomposition discipline before writes;
- `harness` for human approval and permanent safety checks; and
- `integrated-harness` for decomposition, approval, safety, and orchestration.

The Claude marketplace complements the existing Codex marketplace. It does not
replace or alter the top-level Claude copy-in distributions.

## Repository Layout

Claude and Codex remain in one repository with platform-specific packaging and
lifecycle tooling:

```text
claude/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    ├── decomposition-gate/
    ├── harness/
    └── integrated-harness/

scripts/
├── select-claude-mode
└── verify-claude-mode

tests/
├── claude_marketplace_test.sh
├── claude_mode_switch_test.sh
└── claude_guardrail_test.sh
```

Each packaged plugin is complete and independently installable. Runtime files
must resolve through Claude Code's plugin-root mechanism and must not depend on
the repository checkout or the legacy top-level directories. The existing
`decomposition-gate/`, `harness/`, and `integrated-harness/` directories remain
unchanged as supported copy-in distributions.

Platform-neutral fixtures or security test vectors may be shared. Claude and
Codex hook programs remain separate because their event payloads, decisions,
approval semantics, and lifecycle contracts differ.

## Marketplace and Plugin Packaging

The repository exposes one Claude Code marketplace at Claude's native
`.claude-plugin/marketplace.json` path with exactly three local
plugin entries. Each entry identifies one complete plugin package with a valid
manifest, normalized name, and semantic version.

The packages preserve current Claude behavior:

- `decomposition-gate` packages the decomposition protocol and pre-write gate.
- `harness` packages the approval marker gate, destructive-command blocker,
  credential blocker, and supporting guidance.
- `integrated-harness` packages decomposition validation, SHA-256-bound plan
  approval, permanent safety hooks, policy, and orchestration guidance.

Packaged hooks use Claude Code's native plugin-root variable for executable and
resource paths. Files needed at runtime are included within the plugin. Plugin
installation does not silently modify the legacy copy-in files.

Marketplace metadata is distribution metadata, not a mutual-exclusion
mechanism. Documentation therefore directs users to the repository selector for
all routine installation, switching, updating, and removal.

## Mode Selection and Scope

`scripts/select-claude-mode` accepts exactly one managed mode and an optional
scope:

```text
select-claude-mode <mode> [--scope project|local]
select-claude-mode --remove [--scope project|local]
```

The default scope is `project`. `local` is supported for private per-project
activation. `user` is intentionally unsupported because a global mode could
unexpectedly affect unrelated projects.

The selector performs these steps:

1. Validate the requested mode, marketplace, plugin package, Claude CLI
   capabilities, and scope before mutation.
2. Inspect all three managed plugins in every supported scope that can affect
   the current project.
3. Save the relevant pre-operation state for restoration.
4. Disable or remove non-target managed modes that would be effective.
5. Install or update the target from the repository marketplace in the selected
   scope.
6. Run the verifier and require the target to be the only effective managed
   mode.
7. Tell the user to start a new Claude Code session so hooks and plugin content
   reload cleanly.

Project and local state are recorded separately, but mutual exclusion is judged
across their effective combination. A target in one scope conflicts with a
different managed mode in the other scope. The selector resolves managed
conflicts as part of a successful selection and never changes unrelated Claude
plugins.

`--remove` removes all managed modes effective for the current project within
the supported scopes necessary to reach the verified no-mode state. The command
reports each scope it changes. Direct use of Claude's native plugin commands can
bypass these guarantees; the verifier detects the resulting conflict but cannot
prevent it.

## Transaction and Failure Semantics

Preflight errors cause no state change. Cross-mode selection and removal use the
Claude CLI's native lifecycle operations and attempt to restore the previously
effective managed state if a later operation fails.

Restoration is verified rather than assumed. The selector exits unsuccessfully
and distinguishes:

- operation failed and previous state was restored;
- operation failed and restoration was incomplete; and
- update was committed by the native CLI but post-update verification failed.

Same-mode selection is an update. Preflight first requires a coherent effective
state. The native update or install call is treated as the commit point when the
CLI cannot reproduce the previous cached generation. A failure after that point
must not claim rollback.

Malformed CLI output, unavailable required commands, invalid marketplace data,
unsupported scope, missing runtime files, ambiguous installed state, and failed
verification all fail closed with actionable messages. Selector tests run
against isolated fake state and never mutate a developer's installed plugins.

## Verification

`scripts/verify-claude-mode` supports verification of a named effective mode and
of the no-managed-mode state. It inspects both supported scopes affecting the
current project and fails when:

- more than one managed mode is effective;
- a non-target managed mode remains installed or enabled in an effective scope;
- the target is missing or disabled;
- installed package metadata does not match its marketplace identity; or
- required plugin hooks or runtime resources are absent.

The verifier reports scope-specific findings so users can repair state created
by direct native CLI use. It is read-only.

## Compatibility and Maintenance

The marketplace is additive. Existing copy-in commands, paths, settings, plan
files, approval markers, policy files, and documentation remain supported.
Existing Claude smoke and orchestration tests continue to exercise those legacy
distributions.

Packaged files derived from legacy Claude assets receive parity tests for the
security- and protocol-critical content. Packaging-only differences, such as
plugin-root path expansion, are explicitly normalized rather than ignored. This
prevents silent behavioral drift while allowing valid platform packaging.

The project does not claim that regex safety checks form a sandbox. Existing
recommendations for Claude permissions, secret managers, static analysis, and
human review remain applicable.

## Testing

Implementation follows test-driven development. Automated coverage includes:

- marketplace and all three plugin manifest schemas;
- exactly three correctly named local entries and valid semantic versions;
- resolvable, executable hook commands using plugin-root paths;
- all six distinct-mode transitions;
- same-mode updates and committed-update verification failures;
- removal from project and local effective states;
- project/local cross-scope conflict detection and resolution;
- invalid mode, invalid scope, malformed state, CLI failure, and restoration
  reporting;
- preservation of unrelated plugins and configuration;
- decomposition acceptance and rejection cases;
- approval, destructive-command, and plaintext-credential behavior;
- integrated strict and light policy behavior plus SHA-256-bound approval;
- parity between packaged and legacy critical Claude behavior;
- all existing Claude smoke/orchestration tests; and
- all existing Codex marketplace, switching, and guardrail tests.

Where the installed Claude CLI provides safe non-interactive validation, tests
verify its real manifest and marketplace contract. Lifecycle mutation tests use
an isolated fake Claude executable.

## Success Criteria

The feature is complete when:

1. The repository marketplace exposes three valid, independently installable
   Claude Code plugins.
2. Selecting a mode successfully leaves exactly that mode effective across
   supported scopes for the current project.
3. Updating, switching, removing, verifying, and failure recovery have explicit,
   tested outcomes.
4. Packaged plugins preserve the current Claude guardrail behavior and operate
   without repository-relative runtime dependencies.
5. Legacy copy-in installation remains supported and its tests pass unchanged.
6. Codex functionality and tests remain unaffected.
7. Documentation explains native installation, selector usage, scopes, updates,
   removal, verification, session reload, direct-CLI bypass risk, and security
   limitations.
