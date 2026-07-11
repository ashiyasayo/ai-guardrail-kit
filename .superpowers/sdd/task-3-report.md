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

## Review remediation status (2026-07-11)

**BLOCKED.** The Critical human-presence requirement cannot be guaranteed by the
installed Codex hook platform (`codex-cli 0.144.1`). A `PreToolUse` event exposes
session/turn/tool metadata, but no platform-authenticated principal or
human-initiated bit. The installed binary's event schema includes
`session_id`, `transcript_path`, `hook_event_name`, `permission_mode`, `source`,
`turn_id`, and tool data; none distinguishes a command typed by a human from a
command requested by the agent. The same binary exposes native write-capable
tools (`exec_command` and `apply_patch`) and its CLI supports configurations that
run commands without per-command human confirmation.

Consequently, any repository-local approval mechanism that the human can invoke
(a script, executable, file write, environment variable, nonce file, socket, or
local signing key readable/invocable in the guarded environment) can also be
invoked or minted by the agent through `exec_command`/`apply_patch`, unless an
external trusted component withholds that capability. The current
`scripts/approve_plan.py` is therefore demonstrably agent-invocable and cannot
satisfy the requirement. Hook payload fields are untrusted JSON inputs to the
hook and cannot supply the missing trust boundary.

No remediation code was committed for the remaining Important findings because
the task explicitly requires reporting BLOCKED rather than presenting a partial
implementation as secure when this Critical property is unavailable. A viable
continuation requires a Codex platform primitive that emits an authenticated
human approval/token outside guarded tool reach, or a separately trusted
supervisor/credential service whose signing operation is unavailable to every
agent-callable tool.

Evidence commands used:

- `codex --version` -> `codex-cli 0.144.1`
- `codex features list` -> hooks stable; `guardian_approval` stable; no
  human-presence hook feature
- `strings /opt/homebrew/bin/codex` -> native `exec_command` and `apply_patch`
  tool kinds; `PreToolUse` event fields listed above; no authenticated
  human-initiator field
- `codex --help` -> `--ask-for-approval` may be `never`, and
  `--dangerously-bypass-approvals-and-sandbox` exists

## Native `ask` remediation (2026-07-11)

Status changed from the superseded blocker above to **DONE** after the human
selected Codex's native `ask` decision as the trust boundary.

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
- Integrated mode validates the plan markers, parsed policy, canonical allowed
  scopes, patch targets, and policy-derived strict command allowlist before
  returning `ask`. Its reason contains the current plan SHA-256 for audit
  context. Light mode permits only requests that pass the same deterministic
  plan/scope checks. Missing or malformed policy defaults to strict.
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
