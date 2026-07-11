# Task 2 implementation report

## Status

Implemented Task 2: Codex hook protocol normalization and shared security checks.

## Contract evidence

- Installed executable: `/opt/homebrew/Caskroom/codex/0.144.1/bin/codex`
- Installed version: `codex-cli 0.144.1`
- `codex features list` reports `hooks` as `stable` and enabled; the separate legacy `plugin_hooks` feature is removed.
- The installed binary embeds JSON Schema documents titled
  `pre-tool-use.command.input` and `pre-tool-use.command.output`.
- The embedded input schema requires `cwd`, `hook_event_name`, `model`,
  `permission_mode`, `session_id`, `tool_input`, `tool_name`, `tool_use_id`,
  `transcript_path`, and `turn_id`; `hook_event_name` is fixed to
  `PreToolUse`.
- The embedded output schema permits `hookSpecificOutput` with
  `hookEventName: "PreToolUse"`, `permissionDecision` in
  `allow|deny|ask`, and `permissionDecisionReason`.
- The installed binary's command-runner strings distinguish invalid hook JSON
  from normal decisions and explicitly describe tool calls blocked by a
  `PreToolUse` hook.

This evidence establishes the contract used by `hook_protocol.py`; no Claude
exit-code or decision protocol was assumed.

## Files

- Added `shared/codex/hook_protocol.py`
- Added `shared/codex/security_checks.py`
- Added `tests/fixtures/codex/allow.json`
- Added `tests/fixtures/codex/dangerous-command.json`
- Added `tests/fixtures/codex/secret-write.json`
- Added `tests/codex_guardrail_test.sh`
- No existing Claude file was modified.

## RED

Command:

```text
bash tests/codex_guardrail_test.sh shared
```

Result: exit 1 with `FileNotFoundError` for
`shared/codex/hook_protocol.py`, the intended missing-feature failure.

## GREEN

Command:

```text
bash tests/codex_guardrail_test.sh shared && PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile shared/codex/hook_protocol.py shared/codex/security_checks.py && git diff --check
```

Result: exit 0; output included
`PASS: Codex shared hook protocol and security checks`.

## Self-review

- Malformed JSON and invalid/missing project roots fail closed through the
  verified Codex denial object.
- `load_event` validates the required normalized fields used downstream.
- `project_root` resolves an existing directory and rejects missing/invalid
  roots.
- Dangerous-command and secret rules retain the audited Claude semantics but
  expose protocol-independent return values.
- Secret detection returns only a rule name and tests assert the fixture value
  is not returned.
- Placeholder references such as `${API_KEY}` remain allowed.
- Test fixtures contain a structurally realistic but non-live AWS-style value.

## Concerns

- The contract is tied to the locally installed stable hooks implementation in
  Codex CLI 0.144.1. Future CLI upgrades should revalidate the embedded schemas
  before changing this boundary.
- `deny` exits zero because the verified schema communicates the denial on
  stdout; later executable hook tests should validate this end to end through
  Codex when selector configuration is available.

## Review fixes RED/GREEN evidence

RED command:

```text
bash tests/codex_guardrail_test.sh shared
```

RED result: exit 1. The custom stdin stream raised `OSError: read failed`,
which escaped `load_event` instead of producing a verified denial.

GREEN command:

```text
bash tests/codex_guardrail_test.sh shared && PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile shared/codex/hook_protocol.py shared/codex/security_checks.py && git diff --check
```

GREEN result: exit 0 with
`PASS: Codex shared hook protocol and security checks`.

The shared test now also parses every `shared/codex/*.py` file with
`ast.parse(..., feature_version=(3, 9))`, exercises denial output for stdin
read/Unicode/recursion failures, validates required field types and permission
modes, verifies secret denial stdout/stderr never contain the fixture secret,
and rejects nonexistent, regular-file, empty, and non-string project roots.

## Permission-mode review fix RED/GREEN evidence

The installed-schema evidence establishes `permission_mode` as a required
string, but does not establish a closed enum. The validator therefore enforces
the established nonempty-string contract without hard-coding current mode
names, so future Codex modes remain forward compatible.

RED command:

```text
bash tests/codex_guardrail_test.sh shared
```

RED result: exit 1 with
`AssertionError: unfamiliar nonempty permission mode was denied`.

GREEN command:

```text
bash tests/codex_guardrail_test.sh shared && python3 -m py_compile shared/codex/hook_protocol.py shared/codex/security_checks.py
```

GREEN result: exit 0 with
`PASS: Codex shared hook protocol and security checks`.

The regression accepts an otherwise valid event using
`futurePermissionMode`, while the existing coverage continues to deny empty
and non-string `permission_mode` values.
