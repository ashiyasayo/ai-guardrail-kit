# Codex Plugin Marketplace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship three complete, mutually exclusive Codex guardrail plugins from one repository marketplace, with project hooks activated and switched transactionally.

**Architecture:** Each product has an isolated Codex plugin containing one workflow skill and Python hook executables. A repository selector manages Codex plugin installation plus a delimited hook block in project `.codex/config.toml`; a verifier treats those two states as one invariant. Shell tests use a fake `codex` executable and temporary HOME/project directories so developer state is never touched.

**Tech Stack:** Bash, Python 3.9+, JSON, TOML text blocks, Codex CLI/plugin manifests, shell smoke tests

## Global Constraints

- Keep all existing Claude paths and behavior unchanged.
- Support exactly `decomposition-gate`, `harness`, and `integrated-harness`.
- Require Python 3.9 or newer for every Codex mode.
- Never claim that marketplace metadata provides native mutual exclusion.
- Never claim that installing a Codex plugin automatically activates plugin hooks.
- Preserve `.codex/config.toml` content outside the selector-owned block byte-for-byte.
- Reject symlinked or non-regular `.codex/config.toml` targets.
- Use test-first development for every behavior change.

---

### Task 1: Marketplace and Plugin Skeletons

**Files:**
- Create: `marketplaces/codex/marketplace.json`
- Create: `plugins/decomposition-gate/codex/.codex-plugin/plugin.json`
- Create: `plugins/harness/codex/.codex-plugin/plugin.json`
- Create: `plugins/integrated-harness/codex/.codex-plugin/plugin.json`
- Create: `plugins/decomposition-gate/codex/skills/decomposition-gate/SKILL.md`
- Create: `plugins/harness/codex/skills/harness/SKILL.md`
- Create: `plugins/integrated-harness/codex/skills/integrated-harness/SKILL.md`
- Create: `tests/codex_marketplace_test.sh`

**Interfaces:**
- Produces: marketplace name `ai-guardrail-kit`; plugin names identical to the three mode names.
- Produces: each plugin at `plugins/<mode>/codex` with version `0.1.0`.

- [ ] **Step 1: Write the failing marketplace test**

Create a shell test that loads JSON with Python and asserts the marketplace name, exact ordered plugin-name set, local source paths, `AVAILABLE` installation policy, `ON_INSTALL` authentication policy, and `Security` category. For each source path, assert the outer product name equals manifest `name`, version is `0.1.0`, and exactly one `skills/*/SKILL.md` exists with matching frontmatter name.

- [ ] **Step 2: Run the test and verify RED**

Run: `bash tests/codex_marketplace_test.sh`

Expected: FAIL because `marketplaces/codex/marketplace.json` does not exist.

- [ ] **Step 3: Scaffold the three plugins and marketplace**

Use the plugin-creator scaffold script with repo-local paths, then adjust the generated marketplace source paths to:

```json
{"source":"local","path":"../../plugins/decomposition-gate/codex"}
```

and the corresponding paths for the other two modes. Keep unsupported `hooks` out of all three plugin manifests. Each skill must state its scope, its non-sandbox limitation, the required selector command, and that a new thread is required after switching.

- [ ] **Step 4: Validate and verify GREEN**

Run:

```bash
python3 /Users/saiko/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py plugins/decomposition-gate/codex
python3 /Users/saiko/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py plugins/harness/codex
python3 /Users/saiko/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py plugins/integrated-harness/codex
bash tests/codex_marketplace_test.sh
```

Expected: all commands PASS.

- [ ] **Step 5: Commit**

```bash
git add marketplaces plugins tests/codex_marketplace_test.sh
git commit -m "feat: add Codex guardrail marketplace"
```

### Task 2: Codex Hook Protocol and Shared Security Checks

**Files:**
- Create: `plugins/shared/codex/hook_protocol.py`
- Create: `plugins/shared/codex/security_checks.py`
- Create: `tests/fixtures/codex/allow.json`
- Create: `tests/fixtures/codex/dangerous-command.json`
- Create: `tests/fixtures/codex/secret-write.json`
- Create: `tests/codex_guardrail_test.sh`

**Interfaces:**
- Produces: `load_event(stdin) -> dict`, `deny(reason) -> NoReturn`, and `project_root(event) -> pathlib.Path`.
- Produces: `dangerous_command(command) -> str | None`, `pending_content(tool_input) -> str`, and `secret_kind(content) -> str | None`.
- Consumes: Codex hook JSON fields verified from the installed Codex hook contract; normalize them once in `hook_protocol.py` so mode code is protocol-independent.

- [ ] **Step 1: Write failing protocol and security tests**

Add fixture-driven tests that require malformed JSON to fail closed, a harmless read to pass, `git reset --hard` to return the hard-reset rule, a realistic AWS access key to return the AWS rule without echoing the value, and placeholders such as `${API_KEY}` to pass.

- [ ] **Step 2: Run the tests and verify RED**

Run: `bash tests/codex_guardrail_test.sh shared`

Expected: FAIL because `hook_protocol.py` and `security_checks.py` are missing.

- [ ] **Step 3: Implement the minimal shared modules**

Port the audited dangerous-command and secret-detection rules from `harness/.claude/hooks/`, replacing Claude-specific decision JSON with the verified Codex hook result format. Keep secret error output limited to the rule name. Resolve the project root from the Codex event and fail closed when it is absent or invalid.

- [ ] **Step 4: Run and verify GREEN**

Run: `bash tests/codex_guardrail_test.sh shared`

Expected: PASS with no secret value in stdout or stderr.

- [ ] **Step 5: Commit**

```bash
git add plugins/shared tests/fixtures/codex tests/codex_guardrail_test.sh
git commit -m "feat: add Codex hook protocol and security checks"
```

### Task 3: Three Native Guardrail Modes

**Files:**
- Create: `plugins/decomposition-gate/codex/hooks/decomposition_gate.py`
- Create: `plugins/harness/codex/hooks/plan_gate.py`
- Create: `plugins/harness/codex/hooks/block_dangerous_commands.py`
- Create: `plugins/harness/codex/hooks/block_secrets.py`
- Create: `plugins/harness/codex/scripts/approve_plan.py`
- Create: `plugins/integrated-harness/codex/hooks/plan_gate.py`
- Create: `plugins/integrated-harness/codex/hooks/block_dangerous_commands.py`
- Create: `plugins/integrated-harness/codex/hooks/block_secrets.py`
- Create: `plugins/integrated-harness/codex/scripts/approve_plan.py`
- Create: `plugins/integrated-harness/codex/orchestration-policy.md`
- Extend: `tests/codex_guardrail_test.sh`

**Interfaces:**
- Uses project artifacts under `.codex/guardrail/`: `plan/decomposition.md`, `approval.json`, and `orchestration-policy.md`.
- Approval record: `{"plan_sha256":"<64 lowercase hex>","approved_at":<unix seconds>}`.
- Hook exit/result contract is exclusively supplied by `plugins/shared/codex/hook_protocol.py`.

- [ ] **Step 1: Add failing mode tests**

Cover missing/malformed/valid decomposition, plan-file self-write allowance, absent/expired/current approval, approval-file self-write denial, destructive-command denial after approval, credential denial after approval, strict/light integrated behavior, allowed-scope enforcement, and digest invalidation after editing the decomposition file.

- [ ] **Step 2: Run and verify RED**

Run: `bash tests/codex_guardrail_test.sh modes`

Expected: FAIL because mode hook files are missing.

- [ ] **Step 3: Implement decomposition-gate**

Port the marker checks and minimal write-intent detection from the Claude implementation. Change managed paths from `.claude/` to `.codex/guardrail/`. Permit only creation/editing of the decomposition artifact before the gate passes.

- [ ] **Step 4: Implement harness**

Use an approval JSON record created only by `approve_plan.py`; require an age of at most 3600 seconds and deny future timestamps over 60 seconds. Keep read-only command parsing, approval self-protection, dangerous-command blocking, and secret blocking independent.

- [ ] **Step 5: Implement integrated-harness**

Port strict/light policy parsing, plan markers, allowed scopes, strict Bash allowlist, SHA-256 approval binding, permanent command blocking, and secret blocking. Default missing or invalid policy to strict.

- [ ] **Step 6: Run and verify GREEN**

Run:

```bash
bash tests/codex_guardrail_test.sh
bash decomposition-gate/tests/smoke_test.sh
bash integrated-harness/tests/smoke_test.sh
bash integrated-harness/tests/orchestration_test.sh
```

Expected: all Codex and existing Claude tests PASS.

- [ ] **Step 7: Commit**

```bash
git add plugins tests/codex_guardrail_test.sh
git commit -m "feat: port guardrail modes to Codex hooks"
```

### Task 4: Transactional Mode Selector and Verifier

**Files:**
- Create: `scripts/codex-mode-lib.sh`
- Create: `scripts/select-codex-mode`
- Create: `scripts/verify-codex-mode`
- Create: `tests/helpers/fake-codex`
- Create: `tests/codex_mode_switch_test.sh`

**Interfaces:**
- `select-codex-mode <mode> [project-dir]` selects one exact mode.
- `verify-codex-mode [expected-mode] [project-dir]` returns nonzero for zero/multiple installed modes or hook mismatch.
- Managed config delimiters are `# ai-guardrail-kit:begin` and `# ai-guardrail-kit:end` and may appear at most once each.
- Fake Codex state is selected through `AI_GUARDRAIL_TEST_STATE`; production code never requires that variable.

- [ ] **Step 1: Write failing selector tests**

Test invalid mode/no mutation, first install, idempotent selection, all six cross-mode transitions, preservation of prefix/suffix config bytes, rejection of duplicate delimiters and symlink config, plugin-install failure rollback, config-write failure rollback, and verifier detection of plugin/hook mismatch.

- [ ] **Step 2: Run and verify RED**

Run: `bash tests/codex_mode_switch_test.sh`

Expected: FAIL because selector scripts are missing.

- [ ] **Step 3: Implement state inspection and managed-block rendering**

Put shared parsing in `codex-mode-lib.sh`. Render a target-specific Codex hook block referencing absolute installed hook paths. Refuse malformed delimiters, symlinks, non-regular files, and a project path without a writable `.codex` parent.

- [ ] **Step 4: Implement transactional switching**

Validate everything before mutation; snapshot prior managed state; remove non-target plugins; install with `codex plugin add <mode>@ai-guardrail-kit`; write config through `mktemp` in `.codex` plus `mv`; verify final state. On any post-mutation failure, restore both plugin and managed config state and report rollback success separately from switch failure.

- [ ] **Step 5: Implement verification**

Parse `codex plugin list` without matching unrelated names. Require one installed managed mode, one valid managed block, hook commands belonging to that same mode, and executable referenced files.

- [ ] **Step 6: Run and verify GREEN**

Run: `bash tests/codex_mode_switch_test.sh`

Expected: PASS for every transition and rollback case.

- [ ] **Step 7: Commit**

```bash
git add scripts tests/helpers/fake-codex tests/codex_mode_switch_test.sh
git commit -m "feat: add transactional Codex mode switching"
```

### Task 5: Documentation and End-to-End Verification

**Files:**
- Modify: `README.md`
- Create: `docs/codex-marketplace.md`
- Modify: each Codex `SKILL.md` created in Task 1

**Interfaces:**
- Documents marketplace-add, select, verify, update, remove, approval, and new-thread workflows.
- Explicitly documents that direct `codex plugin add/remove` can desynchronize hooks.

- [ ] **Step 1: Add failing documentation assertions**

Extend `tests/codex_marketplace_test.sh` to require README links and documentation containing the exact selector commands, `.codex/config.toml` managed-block warning, direct-CLI limitation, Python minimum, and new-thread instruction.

- [ ] **Step 2: Run and verify RED**

Run: `bash tests/codex_marketplace_test.sh`

Expected: FAIL because `docs/codex-marketplace.md` is missing.

- [ ] **Step 3: Write installation and operations documentation**

Document:

```bash
codex plugin marketplace add "$(pwd)/marketplaces/codex"
./scripts/select-codex-mode decomposition-gate .
./scripts/verify-codex-mode decomposition-gate .
```

Include selection guidance, human-only approval commands, cachebuster/update behavior, safe removal through the selector tooling, rollback messages, limitations, and new-thread activation.

- [ ] **Step 4: Run complete verification**

Run:

```bash
bash tests/codex_marketplace_test.sh
bash tests/codex_guardrail_test.sh
bash tests/codex_mode_switch_test.sh
bash decomposition-gate/tests/smoke_test.sh
bash integrated-harness/tests/smoke_test.sh
bash integrated-harness/tests/orchestration_test.sh
python3 /Users/saiko/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py plugins/decomposition-gate/codex
python3 /Users/saiko/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py plugins/harness/codex
python3 /Users/saiko/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py plugins/integrated-harness/codex
git diff --check
```

Expected: every command exits 0 with no warnings containing `FAIL`, `Traceback`, or malformed-manifest errors.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/codex-marketplace.md plugins/*/codex/skills tests/codex_marketplace_test.sh
git commit -m "docs: document Codex guardrail plugins"
```

- [ ] **Step 6: Request code review**

Invoke `superpowers:requesting-code-review`, address verified findings, rerun the complete verification block, and record the final commands and outputs in the handoff.
