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
