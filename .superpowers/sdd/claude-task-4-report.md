# Claude Task 4 Implementation Report

## Outcome

Implemented transactional Claude mode selection and read-only verification for the `project` and `local` plugin scopes.

## TDD evidence

- Added the `lifecycle` group to `tests/claude_mode_switch_test.sh` before creating either production script.
- Actual RED command: `bash tests/claude_mode_switch_test.sh lifecycle`
- Actual RED result: exit 1 with `scripts/select-claude-mode: No such file or directory`.
- Implemented `scripts/verify-claude-mode` first, followed by `scripts/select-claude-mode`.
- GREEN lifecycle result: `PASS: transactional Claude mode switching`.

## Implemented behavior

- `select-claude-mode <mode> [--scope project|local] [project-dir]`
  - defaults to project scope;
  - rejects invalid modes, unsupported/user scope, missing project directories, unavailable CLI/runtime, malformed list state, and unsupported managed user-scope installations before mutation;
  - snapshots all managed `(mode, scope, enabled)` tuples, including disabled installations;
  - removes managed conflicts and redundant target copies across both supported scopes;
  - installs and enables the requested target in the requested scope;
  - invokes the verifier after mutation;
  - restores the tuple snapshot after switch/removal failure and reports the required exact restoration wording;
  - uses native `claude plugin update` exactly once for a coherent same-mode installation, treating successful return as the irreversible commit point.
- `select-claude-mode --remove ...`
  - removes managed installations from every supported scope;
  - verifies an empty effective managed set;
  - preserves unrelated plugins;
  - reports all scopes changed by the operation.
- `verify-claude-mode`
  - performs no mutation;
  - requires the effective mode set to equal exactly the named target;
  - requires an enabled target installation in project or local scope;
  - validates marketplace and plugin manifest identity;
  - validates every hook referenced from `hooks/hooks.json` exists;
  - emits scope-qualified conflict diagnostics;
  - proves `--no-managed-mode` only when the effective set is empty.

## Test coverage

The lifecycle group covers first install, same-mode update, all six ordered distinct-mode transitions, project/local conflicts in both ownership directions, duplicate same-mode installations, removal, default project and explicit local scope, invalid mode/scope non-mutation, unrelated-plugin preservation, install and remove failures, successful and incomplete restoration, malformed listing output, verifier read-only behavior, and post-commit verification failure wording.

Fresh validation before commit:

```text
bash -n scripts/select-claude-mode scripts/verify-claude-mode tests/claude_mode_switch_test.sh tests/helpers/fake-claude
shellcheck scripts/select-claude-mode scripts/verify-claude-mode tests/claude_mode_switch_test.sh tests/helpers/fake-claude
bash tests/claude_mode_switch_test.sh
bash tests/claude_mode_switch_test.sh lifecycle
bash tests/claude_marketplace_test.sh
bash tests/claude_guardrail_test.sh
```

## Notes and concerns

- Rollback restores the specified logical tuples, not the prior fake/cache generation bytes; reinstalling can legitimately advance a cached generation.
- The selector intentionally rejects managed installations reported in user scope because user scope is unsupported and silently changing it would violate scope ownership.
- Scratch SDD briefs/reviews and the pre-existing `progress.md` modification were excluded from the implementation commit.

## Review remediation

All Task 4 review findings were addressed in a single test-first pass.

### RED

Regression tests and fake-CLI fault/observability support were added before production changes.

```text
$ bash tests/claude_mode_switch_test.sh lifecycle
FAIL: Claude operation ran outside project cwd
```

This was the expected first behavioral failure: selector/verifier lifecycle inspection inherited the invoking shell's directory instead of executing at the selected project root.

### Fixes

- Canonicalize `project-dir` and execute every Claude list/install/update/uninstall/enable/disable call with that exact cwd. The fake CLI can require a project cwd, so this is behavioral rather than log-only coverage.
- Reject every managed user-scope tuple, enabled or disabled, in both named and `--no-managed-mode` verification.
- Added shared strict package validation for marketplace identity/source, target manifest identity, nonempty hook registration, command-hook structure, and every `${CLAUDE_PLUGIN_ROOT}` referenced file. Selector performs it before its first CLI inspection or lifecycle mutation. Tests independently corrupt the marketplace, remove the target manifest, empty hook registration, and remove a referenced hook, proving zero lifecycle calls.
- Restoration now explicitly enables or disables every replayed tuple. The fake install default can be forced enabled, proving disabled snapshots remain disabled.
- Added INT/TERM/HUP traps. Before the same-mode commit point, interruption replays the snapshot; after successful native update return, interruption preserves the update and prints `update applied but verification interrupted`. Deterministic pauses test all six signal/phase combinations and their 130/143/129 statuses.

### GREEN

```text
PASS: Claude scope state adapter
PASS: transactional Claude mode switching
PASS: Claude marketplace packages are complete
PASS: packaged Claude guardrails match legacy behavior
```

Static verification also completed with zero output/errors from `bash -n`, ShellCheck (when available), and `git diff --check`.

## Re-review remediation

### RED

The remaining marketplace and verifier regressions were added before production changes.

```text
$ bash tests/claude_mode_switch_test.sh lifecycle
FAIL: malformed listing misdiagnosed
```

The malformed JSON path was incorrectly reported as an unsupported user-scope installation, demonstrating that schema validation and user-conflict detection were conflated.

### Fixes

- Marketplace validation now first gathers every entry with the managed name, requires exactly one such entry, and only then validates its source. Both a sole wrong-source entry and a duplicate managed name with a different source are rejected through selector and verifier; selector tests prove no lifecycle mutation occurs.
- The verifier now invokes `claude plugin list --json` exactly once. One Python parse validates the complete schema and writes a normalized managed tuple snapshot. User-scope conflicts, supported-scope effective modes, enabled-target proof, and scope-qualified conflict diagnostics are all derived from that immutable snapshot.
- Malformed JSON/schema now emits `malformed Claude plugin state`; user-scope diagnostics are emitted only after successful schema validation.

### GREEN

```text
PASS: transactional Claude mode switching
```

## Final branch remediation

### RED

The final disabled-conflict, lifecycle-message, native-capability, marketplace-registration, and documentation regressions were added before production changes.

```text
$ bash tests/claude_mode_switch_test.sh lifecycle
FAIL: selection omitted session restart
```

### Fixes

- Named verification now rejects every supported-scope non-target managed tuple, including disabled project and local installations, with scope-qualified conflict diagnostics.
- Successful selection, same-mode update, and removal messages explicitly require starting a new Claude Code session.
- Before its first lifecycle mutation, the selector checks the Claude 2.1.207 `list`, `install`, `update`, `uninstall`, `enable`, and `disable` capabilities through nonmutating `--help` calls, then parses `claude plugin marketplace list --json` and proves `ai-guardrail-kit` is registered/resolvable. All checks execute at the canonical project cwd. Missing capabilities and unregistered marketplace tests prove lifecycle state remains untouched.
- Task 5 documentation assertions now couple distinctive wording to same-mode semantics, all lifecycle restart cases, the three named legacy distributions, unsupported user-scope behavior, and the exact native lifecycle commands that bypass mutual exclusion.

### GREEN

```text
PASS: Claude scope state adapter
PASS: transactional Claude mode switching
PASS: Claude marketplace packages are complete
PASS: packaged Claude guardrails match legacy behavior
PASS: transactional Codex mode switching
PASS: Codex marketplace and plugin skeletons
PASS: Codex shared hook protocol and security checks
PASS: Codex standalone guardrail mode checks
✔ Validation passed
```

The legacy decomposition and integrated-harness smoke/orchestration suites also completed with zero failures.
