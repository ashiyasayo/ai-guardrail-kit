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

## Review remediation

- Signal traps for INT, TERM, and HUP now run rollback and retain conventional
  exit statuses 130, 143, and 129.
- Hook commands are shell-argument quoted and then TOML-string escaped; tests
  cover spaces, quotes, backslashes, command substitution, backticks, and
  semicolons without executing path content.
- Plugin JSON is schema-checked for exact `pluginId`, matching name and
  marketplace, explicit boolean `installed`/`enabled`, and uniqueness.
- Rollback treats inspection and every mutation/restore/verification error as a
  rollback failure and finishes with exact managed-plugin and config comparison.
- Forward and rollback config replacement both use a same-directory temporary
  file and atomic rename, preserving original permission mode. The `.codex`
  directory and config are revalidated immediately before each replacement.

Portable shell cannot fully eliminate the final pathname race between the last
symlink check and `mv(1)` because it lacks directory-fd-relative, no-follow
rename operations. The implementation minimizes this interval and rejects both
`.codex` and config symlinks at initial validation and immediately before every
forward or rollback filesystem mutation. A native helper using `openat(2)` and
`renameat(2)` would be required to close that residual boundary completely.

## Blocking product-fix addendum

Added selector-owned transactional `--remove` and corrected same-mode refresh:
it prevalidates exact state, does not rewrite config or remove the target, and
treats official add as the irreversible commit point. The fake CLI tracks content
generations, proving failed add preserves old content and successful add advances
it. Post-check failure reports an applied update without false rollback.

Post-add signal handling now observes the same irreversible boundary. Once the
official add command returns successfully, INT, TERM, and HUP exit with
130/143/129, report that the update was applied but verification was
interrupted, and preserve the new cached-content generation. Deterministic fake
CLI delay markers cover all three signals without changing cross-mode or remove
rollback behavior.
