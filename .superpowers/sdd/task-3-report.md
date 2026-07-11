# Task 3 Report: Three Native Guardrail Modes

## Status

**DONE.** Implemented the decomposition gate, harness, and integrated harness as native Codex hooks. Guarded operations use Codex's native `ask` decision; permanent dangerous-command, secret, path-containment, and malformed-input checks deny independently.

## TDD evidence

- Initial RED/GREEN established the three standalone native modes.
- Remediation RED: adversarial `diff --output=stolen a b` was incorrectly classified read-only, proving the incomplete option audit.
- Remediation GREEN: disallowed output/execution flags, shell operators, light-mode shell mutation, and canonical `bash tests/` containment cases pass.

## Runtime packaging decision

Marketplace installations cache each plugin independently, so repository-level `shared/codex` cannot be a runtime dependency. Each plugin therefore carries a small local `hooks/hook_protocol.py`; harness plugins also carry local `security_checks.py`. The authoritative repository modules remain `shared/codex/hook_protocol.py` and `shared/codex/security_checks.py`. The mode test copies only `codex/plugins` into a temporary standalone installation and executes every hook there, exercising protocol/security behavior and preventing accidental repository-relative imports. Shared-module tests remain in the same suite for semantic parity.

## Files

- Added decomposition-gate protocol and gate hook.
- Added harness protocol/security modules, plan gate, and dangerous/secret hooks.
- Added integrated-harness protocol/security modules, plan gate, and orchestration policy.
- Extended `tests/codex_guardrail_test.sh` with `shared`, `modes`, and default `all` sections plus Python 3.9 parsing.

## Self-review

- Harness read-only classification rejects shell operators and every audited output/execution option, including Git `--output`, `--ext-diff`, `--textconv`, `--pre`, and `--hostname-bin`.
- Missing or invalid integrated policy defaults to strict. Light allows only deterministically scoped patches without prompting; mutating native shell commands return `ask` because their complete filesystem effects cannot be proven.
- The strict `bash tests/` exception uses canonical containment beneath the project test directory and rejects traversal, absolute paths, operators, and similarly prefixed directories.
- Claude files were read as semantic sources and were not modified.
- Plugin hooks were executed from a copied standalone plugin directory.

## Concerns

- Local runtime copies intentionally duplicate the stable shared boundary. Future shared protocol/security changes must update packaged copies and their standalone parity tests together.
- Codex plugin installation does not itself activate hooks; selector/configuration work remains outside Task 3.

## Native `ask` trust boundary

The implementation intentionally uses Codex's native `ask` decision instead of
a repository-local approval file or script, which would be agent-invocable.

### RED/GREEN evidence

- RED: the amended native-mode test failed at the first `apply_patch` event
  because the old implementation recognized only Claude-style `Write` and
  `Bash` payloads.
- GREEN: `bash tests/codex_guardrail_test.sh modes` passes with native
  `apply_patch.patch` and `exec_command.cmd` fixtures.
- Complete verification passes: the full Codex suite, Claude decomposition
  smoke (14/14), Claude integrated smoke (136/136), and Claude orchestration
  contract (0 failures).

### Fixes and security evidence

- Removed both Codex `approve_plan.py` files and all approval-record behavior.
- Harness asks through native Codex for every classified write-capable request;
  only narrowly parsed read commands pass silently. Compound shell syntax and
  mutating `git branch` forms cannot exploit substring classification.
- Integrated mode validates plan markers, parsed policy, canonical scopes,
  patch targets, and the strict command allowlist before returning `ask`. Its
  reason contains the current plan SHA-256 for audit context. Light permits
  in-scope patches without prompting, while mutating shell requests still ask.
- Native payload schemas are checked. Unknown tools fail closed unless they are
  explicitly proven read-only. Patch paths are project-relative and canonical;
  traversal, absolute paths, and symlink escapes are denied. The decomposition
  self-write exemption matches the exact project-relative path only and rejects
  a symlink target.
- Dangerous-command and secret hooks consume native `cmd` and `patch` fields and
  remain independent of plan approval eligibility.
- Every installed `hook_protocol.py` and `security_checks.py` is byte-identical
  to its shared audited source, with standalone-install byte-equality tests to
  prevent packaging drift.

### Remaining boundary

Native `ask` is a platform approval request, not a substitute for Codex runtime
configuration. An operator who globally disables platform approvals also
disables that human-interaction boundary; deterministic deny checks remain.

## Final verification (2026-07-11)

- `bash tests/codex_guardrail_test.sh`: shared and standalone mode suites pass.
- `bash tests/codex_marketplace_test.sh`: marketplace/plugin skeleton suite passes.
- `bash decomposition-gate/tests/smoke_test.sh`: 14 passed, 0 failed.
- `bash integrated-harness/tests/smoke_test.sh`: 136 passed, 0 failed.
- `bash integrated-harness/tests/orchestration_test.sh`: 0 failed.
