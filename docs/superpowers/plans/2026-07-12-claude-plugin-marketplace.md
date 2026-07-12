# Claude Plugin Marketplace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship three complete Claude Code guardrail plugins from one marketplace with safe, mutually exclusive project/local selection while preserving legacy copy-in installation.

**Architecture:** Add an isolated `claude/` distribution whose plugins package the existing Claude hooks with plugin-root path resolution. A Bash selector uses the native Claude plugin lifecycle and a read-only verifier enforces one effective managed mode across project and local scopes; fake-CLI tests isolate all mutations from the developer environment.

**Tech Stack:** Bash, Python 3.8+/3.9+, JSON, Claude Code plugin manifests and CLI, shell smoke tests

## Global Constraints

- Preserve the current top-level `decomposition-gate/`, `harness/`, and `integrated-harness/` copy-in distributions and behavior.
- Support exactly `decomposition-gate`, `harness`, and `integrated-harness`.
- Default selection to `project`; support `local`; reject `user`.
- Judge mutual exclusion across the effective combination of project and local scopes.
- Never claim marketplace metadata natively enforces mutual exclusion.
- Never modify unrelated Claude plugins or Codex files.
- Packaged runtime files must use `${CLAUDE_PLUGIN_ROOT}` and must not depend on the repository checkout.
- Require Python 3.8+ for decomposition-gate/harness and Python 3.9+ for integrated-harness, matching the legacy distributions.
- Use test-driven development for every behavior change.

---

### Task 1: Marketplace and Complete Plugin Packages

**Files:**
- Create: `claude/.claude-plugin/marketplace.json`
- Create: `claude/plugins/decomposition-gate/.claude-plugin/plugin.json`
- Create: `claude/plugins/harness/.claude-plugin/plugin.json`
- Create: `claude/plugins/integrated-harness/.claude-plugin/plugin.json`
- Create: `claude/plugins/decomposition-gate/hooks/hooks.json`
- Create: `claude/plugins/harness/hooks/hooks.json`
- Create: `claude/plugins/integrated-harness/hooks/hooks.json`
- Copy/package: runtime files from each top-level `<mode>/.claude/` into `claude/plugins/<mode>/`
- Create: `tests/claude_marketplace_test.sh`

**Interfaces:**
- Produces marketplace identity `ai-guardrail-kit` and plugin identities equal to the three mode names, version `0.1.0`.
- Produces native hook commands of the form `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/<file>.py"`.
- Produces self-contained packages; `${CLAUDE_PROJECT_DIR}` remains valid only for project-owned plan, policy, and approval state.

- [ ] **Step 1: Write the failing marketplace/package test**

Create `tests/claude_marketplace_test.sh` with a Python JSON assertion block that requires the exact three marketplace entries, local source paths `./plugins/<mode>`, matching manifest names/versions, and a `hooks/hooks.json` in every plugin. Assert every hook command begins with `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/`, every referenced executable exists, and no packaged runtime file contains `$CLAUDE_PROJECT_DIR/.claude/hooks/`.

- [ ] **Step 2: Run the test and verify RED**

Run: `bash tests/claude_marketplace_test.sh`

Expected: FAIL because `claude/.claude-plugin/marketplace.json` does not exist.

- [ ] **Step 3: Add manifests, hook registration, and packaged assets**

Create the marketplace and manifests using the installed Claude Code schema. Translate each legacy `settings.json` hook entry into native plugin `hooks/hooks.json`; for example:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit|Bash",
        "hooks": [{
          "type": "command",
          "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/decomposition_gate.py\"",
          "timeout": 10
        }]
      }
    ]
  }
}
```

Package the existing hooks, plan templates, protocols, policies, and orchestration documents required by each product. Change only runtime hook-location references needed for plugin packaging.

- [ ] **Step 4: Validate against the installed Claude CLI and verify GREEN**

Run:

```bash
claude plugin validate --strict claude/.claude-plugin/marketplace.json
bash tests/claude_marketplace_test.sh
```

Expected: both commands exit 0 under Claude Code 2.1.207 or newer.

- [ ] **Step 5: Commit**

```bash
git add claude tests/claude_marketplace_test.sh
git commit -m "feat: add Claude guardrail marketplace"
```

### Task 2: Packaged Guardrail Behavior and Legacy Parity

**Files:**
- Modify: packaged hook files under `claude/plugins/*/hooks/` only where plugin-root resolution requires it
- Create: `tests/claude_guardrail_test.sh`
- Create: `tests/fixtures/claude/allow.json`
- Create: `tests/fixtures/claude/dangerous-command.json`
- Create: `tests/fixtures/claude/secret-write.json`

**Interfaces:**
- Consumes native Claude `PreToolUse` JSON on stdin and legacy project state under `$CLAUDE_PROJECT_DIR/.claude/`.
- Produces the same exit codes and hook decision JSON as the corresponding top-level Claude hook.
- Parity normalization permits only packaged hook path differences; security patterns and decision behavior must match.

- [ ] **Step 1: Write failing fixture and parity tests**

Require packaged decomposition-gate to reject missing/malformed plans and accept a valid plan; harness to reject unapproved writes, destructive Bash, and realistic plaintext credentials; integrated-harness to enforce strict/light policy and SHA-256-bound approval. Run each fixture through both the legacy and packaged hook and compare exit status plus normalized decision/reason fields. Add a source-parity assertion for `block_dangerous_commands.py` and `block_secrets.py` after normalizing plugin-only path strings.

- [ ] **Step 2: Run and verify RED**

Run: `bash tests/claude_guardrail_test.sh`

Expected: FAIL on missing packaged behavior or an unnormalized runtime path.

- [ ] **Step 3: Make packaged hooks self-contained without semantic changes**

Retain project state paths such as:

```python
project_dir = Path(os.environ["CLAUDE_PROJECT_DIR"])
plan_path = project_dir / ".claude" / "plan" / "decomposition.md"
```

Do not replace project artifacts with plugin package paths. Only executable/resource assets shipped by the plugin resolve beneath `CLAUDE_PLUGIN_ROOT` through hook registration.

- [ ] **Step 4: Run packaged and legacy regression suites**

Run:

```bash
bash tests/claude_guardrail_test.sh
bash decomposition-gate/tests/smoke_test.sh
bash integrated-harness/tests/smoke_test.sh
bash integrated-harness/tests/orchestration_test.sh
```

Expected: all commands PASS with no credential value echoed.

- [ ] **Step 5: Commit**

```bash
git add claude/plugins tests/fixtures/claude tests/claude_guardrail_test.sh
git commit -m "test: verify packaged Claude guardrails"
```

### Task 3: Scope-Aware State Adapter and Fake Claude CLI

**Files:**
- Create: `scripts/claude-mode-lib.sh`
- Create: `tests/helpers/fake-claude`
- Create: `tests/claude_mode_switch_test.sh`

**Interfaces:**
- Produces `agk_claude_modes`, `agk_claude_validate_scope`, `agk_claude_list_scope <scope>`, `agk_claude_is_enabled <mode> <scope>`, and `agk_claude_effective_modes`.
- Fake state root is selected only through `AI_GUARDRAIL_CLAUDE_TEST_STATE`; production use does not require it.
- CLI output parsing consumes `claude plugin list --json`, verified with Claude Code 2.1.207, rather than informal substring matching.

- [ ] **Step 1: Write failing state-adapter tests**

Add cases for empty state, one project mode, one local mode, the same mode in both scopes, two different cross-scope modes, unrelated plugins, malformed CLI JSON/text, and rejected `user` scope. Require exact names so `harness-extra` never matches `harness`.

- [ ] **Step 2: Run and verify RED**

Run: `bash tests/claude_mode_switch_test.sh state`

Expected: FAIL because the library and fake CLI are missing.

- [ ] **Step 3: Implement the fake lifecycle contract**

Support `plugin marketplace add --scope`, `plugin list --json`, `plugin install --scope`, `plugin update`, `plugin uninstall --scope`, `plugin enable --scope`, and `plugin disable --scope`. Persist JSON state separately for `project` and `local`. Add deterministic failure controls:

```text
FAKE_CLAUDE_FAIL_INSTALL=<mode>
FAKE_CLAUDE_FAIL_REMOVE=<mode>
FAKE_CLAUDE_CORRUPT_LIST=1
FAKE_CLAUDE_COMMIT_THEN_FAIL_VERIFY=1
```

- [ ] **Step 4: Implement strict state parsing**

Define the managed set once as a newline-safe Bash array. Reject scope values other than `project` and `local`. Parse only native `plugin list --json` output and fail closed on malformed or missing fields. `agk_claude_effective_modes` returns unique enabled managed names across both scopes.

- [ ] **Step 5: Run and verify GREEN**

Run: `bash tests/claude_mode_switch_test.sh state`

Expected: PASS for all scope and malformed-output cases.

- [ ] **Step 6: Commit**

```bash
git add scripts/claude-mode-lib.sh tests/helpers/fake-claude tests/claude_mode_switch_test.sh
git commit -m "test: model Claude plugin scope state"
```

### Task 4: Transactional Selector and Read-Only Verifier

**Files:**
- Create: `scripts/select-claude-mode`
- Create: `scripts/verify-claude-mode`
- Extend: `tests/claude_mode_switch_test.sh`

**Interfaces:**
- `select-claude-mode <mode> [--scope project|local] [project-dir]` selects or updates one effective mode.
- `select-claude-mode --remove [--scope project|local] [project-dir]` reaches a verified no-managed-mode state and reports every changed scope.
- `verify-claude-mode <mode> [project-dir]` and `verify-claude-mode --no-managed-mode [project-dir]` are read-only.
- Exit 0 means the requested effective invariant is proven; every unknown/ambiguous state exits nonzero.

- [ ] **Step 1: Add failing lifecycle tests**

Cover first install, same-mode update, all six distinct-mode transitions, project/local conflicts in both directions, duplicate same-mode installations, `--remove`, invalid mode/scope with no mutation, unrelated plugin preservation, install/remove failures, successful restoration, incomplete restoration, malformed list output, and committed-update/post-verification failure wording.

- [ ] **Step 2: Run and verify RED**

Run: `bash tests/claude_mode_switch_test.sh lifecycle`

Expected: FAIL because selector and verifier do not exist.

- [ ] **Step 3: Implement read-only verification first**

For a named target, require `agk_claude_effective_modes` to equal exactly that target, require at least one enabled target installation in the supported scopes, validate its marketplace identity, and check every manifest-referenced hook/resource exists. For `--no-managed-mode`, require the effective set to be empty. Print scope-qualified diagnostics such as `conflict: harness (local)`.

- [ ] **Step 4: Implement selection preflight and switching**

Resolve the repository root from the selector script, validate the marketplace/package, CLI commands, project directory, and both scope states before mutation. Snapshot managed `(mode, scope, enabled)` tuples. Remove/disable every non-target effective managed installation, install or enable the target in the requested scope, remove redundant target copies that could obscure ownership, then invoke the verifier.

- [ ] **Step 5: Implement restoration and update commit-point reporting**

On cross-mode/removal failure, replay the saved tuples and verify them. Emit exactly one of:

```text
selection failed; previous managed state restored
selection failed; managed state restoration incomplete
update applied but verification failed
```

For coherent same-mode selection, perform preflight without mutation, call the native update/install once, and treat its successful return as the irreversible cached-generation commit point.

- [ ] **Step 6: Run and verify GREEN**

Run: `bash tests/claude_mode_switch_test.sh`

Expected: PASS for every transition, scope conflict, removal, and failure case.

- [ ] **Step 7: Commit**

```bash
git add scripts/select-claude-mode scripts/verify-claude-mode tests/claude_mode_switch_test.sh
git commit -m "feat: add transactional Claude mode switching"
```

### Task 5: Documentation, Full Verification, and Review

**Files:**
- Create: `docs/claude-marketplace.md`
- Modify: `README.md`
- Extend: `tests/claude_marketplace_test.sh`

**Interfaces:**
- Documents marketplace registration, selector, verifier, update, removal, project/local scope, session restart, legacy copy-in, and direct-native-CLI bypass risk.
- Leaves `docs/codex-marketplace.md` and Codex command behavior unchanged.

- [ ] **Step 1: Add failing documentation assertions**

Require README to link `docs/claude-marketplace.md`. Require that document to contain executable examples for marketplace registration, all three selections, `--scope local`, verification, `--remove`, same-mode update, session restart, copy-in compatibility, unsupported `user`, and the warning that direct native commands bypass selector mutual exclusion.

- [ ] **Step 2: Run and verify RED**

Run: `bash tests/claude_marketplace_test.sh`

Expected: FAIL because `docs/claude-marketplace.md` is missing.

- [ ] **Step 3: Write operations documentation**

Use the exact installed CLI syntax established in Tasks 1 and 3. Show repository commands in this order:

```bash
./scripts/select-claude-mode decomposition-gate --scope project .
./scripts/verify-claude-mode decomposition-gate .
./scripts/select-claude-mode --remove --scope project .
```

Explain that selecting the current mode performs an update and that users must start a new Claude Code session after any successful lifecycle change.

- [ ] **Step 4: Run complete verification**

Run:

```bash
bash tests/claude_marketplace_test.sh
bash tests/claude_guardrail_test.sh
bash tests/claude_mode_switch_test.sh
bash decomposition-gate/tests/smoke_test.sh
bash integrated-harness/tests/smoke_test.sh
bash integrated-harness/tests/orchestration_test.sh
bash tests/codex_marketplace_test.sh
bash tests/codex_guardrail_test.sh
bash tests/codex_mode_switch_test.sh
claude plugin validate --strict claude/.claude-plugin/marketplace.json
git diff --check
```

Expected: every command exits 0; no output contains `FAIL`, `Traceback`, leaked fixture credentials, malformed manifest errors, or unverified rollback claims.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/claude-marketplace.md tests/claude_marketplace_test.sh
git commit -m "docs: document Claude guardrail plugins"
```

- [ ] **Step 6: Request code review**

Invoke `superpowers:requesting-code-review`, address only verified findings, rerun the complete verification block, and record exact final results in the handoff.
