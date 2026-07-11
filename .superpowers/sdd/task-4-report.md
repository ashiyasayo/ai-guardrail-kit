# Task 4 Report: Transactional Codex Mode Selector

## Status

Implemented the transactional selector and verifier for exactly
`decomposition-gate`, `harness`, and `integrated-harness`.

## RED / GREEN

- RED: `bash tests/codex_mode_switch_test.sh` failed because
  `scripts/select-codex-mode` did not exist.
- GREEN: the same test passes all first-install, idempotence, six cross-mode
  transitions, delimiter/config-target rejection, unrelated-plugin preservation,
  mismatch detection, and rollback cases.

## Codex 0.144.1 Hook Schema Evidence

- `codex --version` reported `codex-cli 0.144.1`.
- The installed user configuration contains a live matcher group expressed as
  `[[hooks.SessionStart]]`, followed by a nested command handler expressed as
  `[[hooks.SessionStart.hooks]]`, with `type = "command"` and `command = ...`.
- Strings embedded in the installed 0.144.1 executable identify `PreToolUse` as
  a supported hook event and identify the TOML structures
  `ConfiguredHookMatcherGroup`, `HookHandlerConfig::Command`, `matcher`,
  `command`, and `timeout`.
- Loading the exact override shape
  `hooks.PreToolUse=[{matcher="exec_command|apply_patch",hooks=[{type="command",command="python3 /tmp/example.py"}]}]`
  through `codex --strict-config ... doctor` reached the doctor report without a
  configuration/schema error. (`features` itself rejects `--strict-config`, so
  `doctor` was used for this validation.)

The generated TOML therefore uses only the evidenced matcher-group and nested
command-handler keys. Plugin manifests remain hook-free; selection explicitly
activates project hooks.

## Transaction and Rollback Coverage

- Invalid mode: validation occurs before mutation.
- Plugin add failure: prior plugin set and exact config bytes are restored.
- Plugin remove failure: no config mutation occurs and prior state remains.
- Injected config-write failure after plugin mutation: prior plugin set and
  exact config bytes are restored.
- Final verification failure enters the same rollback path.
- Only the three `@ai-guardrail-kit` plugin IDs are inspected or changed;
  unrelated installed plugins survive selection.

## Self-review

- Config parsing rejects duplicate, orphaned, reversed, inline, symlinked, and
  non-regular managed targets.
- Replacement preserves bytes before and after the unique managed block and
  uses `mktemp` in `.codex` followed by `mv`.
- Verification uses exact JSON fields from `codex plugin list --json`, not
  substring matching, and checks exact rendered block equality, Python 3.9+,
  and executable hook entrypoints.
- The fake CLI models the installed-list JSON shape and independently injectable
  list/add/remove failures.

## Concerns

The selector references the repository-local marketplace hook paths, so moving
or deleting the repository after selection invalidates verification and hook
execution. This is intentional for the repository-local marketplace model and
is detected by `verify-codex-mode`.
