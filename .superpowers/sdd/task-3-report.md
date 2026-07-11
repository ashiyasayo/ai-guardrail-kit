# Task 3 Report: Three Native Guardrail Modes

## Status

Implemented the decomposition gate, harness, and integrated harness Codex hook modes, including human approval scripts, integrated policy, permanent dangerous-command and secret checks, and Python 3.9 syntax verification.

## TDD evidence

- RED: `bash tests/codex_guardrail_test.sh modes` failed because `codex/plugins/decomposition-gate/hooks/decomposition_gate.py` did not exist in the standalone copied plugin tree.
- GREEN: `bash tests/codex_guardrail_test.sh modes` passed with `PASS: Codex standalone guardrail modes (22 assertions)`.
- Full regression: Codex shared/mode tests passed; Claude decomposition smoke passed 14/14; Claude integrated smoke passed 136/136; Claude orchestration contract passed with 0 failures.

## Runtime packaging decision

Marketplace installations cache each plugin independently, so repository-level `shared/codex` cannot be a runtime dependency. Each plugin therefore carries a small local `hooks/hook_protocol.py`; harness plugins also carry local `security_checks.py`. The authoritative repository modules remain `shared/codex/hook_protocol.py` and `shared/codex/security_checks.py`. The mode test copies only `codex/plugins` into a temporary standalone installation and executes every hook there, exercising protocol/security behavior and preventing accidental repository-relative imports. Shared-module tests remain in the same suite for semantic parity.

## Files

- Added decomposition-gate protocol and gate hook.
- Added harness protocol/security modules, plan gate, dangerous/secret hooks, and approval script.
- Added integrated-harness protocol/security modules, plan gate, dangerous/secret hooks, approval script, and orchestration policy.
- Extended `tests/codex_guardrail_test.sh` with `shared`, `modes`, and default `all` sections plus Python 3.9 parsing.

## Self-review

- All approval writes use the exact JSON keys, a lowercase SHA-256 hex digest, and integer Unix seconds.
- Approval is content-bound, rejects records older than 3600 seconds and timestamps over 60 seconds in the future, and cannot be changed through file/Bash hooks.
- Missing or invalid integrated policy defaults to strict; light bypasses approval/scope but not independent secret/danger hooks.
- Claude files were read as semantic sources and were not modified.
- Plugin hooks were executed from a copied standalone plugin directory.

## Concerns

- Local runtime copies intentionally duplicate the stable shared boundary. Future shared protocol/security changes must update packaged copies and their standalone parity tests together.
- Codex plugin installation does not itself activate hooks; selector/configuration work remains outside Task 3.
