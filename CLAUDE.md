# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`ai-guardrail-kit` ships four **mutually exclusive** governance modes for AI coding agents, implemented across three platforms (Claude Code, Codex, GitHub Copilot/VS Code). Claude and Codex carry all four modes; Copilot is experimental/Preview and currently carries two (`decomposition-gate`, `sensitive-data-guard`). The four modes, from lightest to most complete:

- `decomposition-gate` — forces a written task decomposition (with `## 已知資訊`, `## 缺少的資訊`, and at least one `【假設】` marker) before write-tool use. Process discipline only, no human approval gate.
- `sensitive-data-guard` — blocks hardcoded secrets/credentials in writes and PII in prompts. No approval, no decomposition. **Write-content PII behaves differently per platform**: Claude/Codex redact it and allow; Copilot denies instead, because the `updatedInput` rewrite mechanism is unverified on VS Code and would fail *open* (allowing unredacted content silently) if it stopped working.
- `harness` — human-approval gate (`touch .claude/.plan_approved`) plus permanent dangerous-command and secret blocking. No decomposition requirement.
- `integrated-harness` — everything above, plus a lean `orchestration-policy.md` (strict/standard/light approval modes) and a SessionStart-injected reasoning protocol.

These are **not** additive feature flags — within one platform, exactly one mode is active at a time. Claude and Codex enforce this via the mode-selector scripts; Copilot is copy-in with no selector, so mutual exclusion is the installer's responsibility (both Copilot modes register `PreToolUse` and ship `hook_protocol.py`, so copying both into `.github/hooks/` collides).

This repo (`ai-guardrail-kit` itself) runs `integrated-harness` in `strict` mode via `.claude/orchestration-policy.md`, so editing files under this repo's own `.claude/` is itself gated (decomposition doc + human-run `approve_plan.py`, SHA-256-bound, 60 min TTL). Practical consequence: general `Bash` is refused outside the policy's allowlist — you can run `bash tests/…`, `dotnet`, and `npm` entry points, but **not `git`** (read-only `git status`/`log`/`diff`/`show` are allowed). Commits must be run by the human.

## Repository layout (source of truth vs. published copies)

Read `AGENTS.md` and `ARCHITECTURE.md` before changing any hook/protocol/skill — this is the single most important structural fact about the repo:

- **`shared/claude/`** — single source of truth for Claude's PII trio (`pii_patterns.py`, `block_pii_prompt.py`, `redact_sensitive_info.py`). Never edit the 5 published copies (3 plugin + 2 copy-in) directly; edit here, then run `scripts/sync-claude-hook-copies`.
- **`shared/codex/`** — single source of truth for Codex's equivalent hooks; sync with `scripts/sync-codex-hook-copies`.
- **`shared/copilot/`** — single source of truth for Copilot's `hook_protocol.py` (both modes) and `pii_patterns.py` (sensitive-data-guard only); sync with `scripts/sync-copilot-hook-copies`. The **launchers (`launch.ps1`/`launch.sh`) are deliberately NOT shared**: the Windows launcher is the highest-risk artifact of the Copilot port, and since the two modes are never installed together, cross-mode divergence carries no runtime interaction risk. `sensitive-data-guard`'s launcher is parameterized (two entry points, and the error-path `hookEventName` differs per event).
- **PII rules exist in three near-identical copies** (`shared/claude/`, `shared/codex/`, `shared/copilot/`) because the platforms' hook I/O contracts differ. Their regexes and masking output are identical and must stay that way — `tests/pii_cross_platform_parity_test.sh` enforces this with a shared corpus. Changing one without the others will fail that test.
- **`decomposition-gate/`, `harness/`, `integrated-harness/`** — Claude copy-in source dirs (`.claude/` ready to `cp -r`).
- **`claude/plugins/`, `codex/plugins/`, `copilot/plugins/`** — marketplace/plugin published copies.
- **`block_secrets.py` / `block_dangerous_commands.py`** — deliberately divergent branches between copy-in and plugin (not synced by script); guarded instead by behavioral parity tests.
- **`integrated-harness/plan_gate.py`** approval-path string differs between copy-in (`.claude/hooks/`) and plugin (`${CLAUDE_PLUGIN_ROOT}`/`__file__`-resolved) — known, intentional exception.

**Whenever you touch a hook, protocol, or skill, you must check the full "platform × mode × distribution" matrix** described in `AGENTS.md` before considering the change complete — do not fix one copy and stop.

## Common commands

Run the default smoke regression suite (the canonical entry point for push/PR and routine manual regression):

```bash
bash tests/run_all.sh
```

Run the complete mode-switch regression when needed:

```bash
AGK_TEST_PROFILE=full bash tests/run_all.sh
```

Run one test file directly, e.g.:

```bash
bash tests/claude_guardrail_test.sh
bash tests/claude_shared_sync_test.sh      # verifies shared/claude/ synced into all 5 copies
bash tests/claude_copyin_parity_test.sh    # verifies copy-in vs plugin byte-for-byte parity
bash tests/claude_hook_parity_test.sh      # behavioral parity for the divergent security hooks
bash tests/codex_shared_sync_test.sh
bash tests/copilot_shared_sync_test.sh     # verifies shared/copilot/ synced into both modes
bash tests/copilot_decomposition_gate_test.sh
bash tests/copilot_sensitive_data_guard_test.sh
bash tests/pii_cross_platform_parity_test.sh   # Claude/Codex/Copilot PII rules must agree
```

The two `copilot_*_test.sh` files are thin wrappers around each mode's own `tests/smoke_test.sh`, so the test logic lives in one place. Note that `bash copilot/plugins/…/tests/smoke_test.sh` cannot be run directly under this repo's `strict` policy (only `bash tests/…` is allowlisted) — use the wrappers.

`tests/run_all.sh` defaults to the `smoke` profile and applies a per-test timeout
(`AGK_TEST_TIMEOUT`, default 2400s). Smoke skips `claude_mode_switch_test.sh` and
`codex_mode_switch_test.sh`; use the `full` profile for those complete mode-switch checks.
The Codex test is legitimately slow on Windows/Git Bash (~1170s measured, many Python
interpreter spawns), not hung; a recent isolated optimized run measured ~955s on the same
host, while full-run timings remain sensitive to host I/O.

After editing `shared/claude/*`, `shared/codex/*`, or `shared/copilot/*`, always run the corresponding sync script before testing:

```bash
scripts/sync-claude-hook-copies            # apply
scripts/sync-claude-hook-copies --check    # verify (same as claude_shared_sync_test.sh)
scripts/sync-codex-hook-copies
scripts/sync-codex-hook-copies --check
scripts/sync-copilot-hook-copies
scripts/sync-copilot-hook-copies --check
```

Mode selection / verification (used when testing installs, not for routine hook edits):

```bash
./scripts/select-claude-mode <mode> --scope project .
./scripts/verify-claude-mode <mode> .
./scripts/select-codex-mode <mode> .
./scripts/verify-codex-mode <mode> .
```

No build step and no runtime dependencies beyond Python 3.9+ stdlib — hooks intentionally use no third-party packages.

## Editing tests: two non-obvious constraints

Both look like clutter you'd want to tidy up. Tidying them silently breaks the tests. See `.docs/vault/gotchas/2026-07-31-git-bash-posix-path-via-stdin.md`.

1. **Sensitive test samples are written as adjacent string fragments** (e.g. an ID split into `"A" "123456789"`) so the file never contains a continuous literal. This repo runs its own guardrails against itself: `block_secrets` would *refuse* the write, and `redact_sensitive_info` would *silently mask* PII literals — corrupting the corpus in a way that is easy to miss. Joining the fragments into one string breaks the test.

2. **"Should be denied" assertions must match a reason-specific substring**, never just `permissionDecision": "deny"`. A blanket denial from an unrelated cause (a `cwd` that fails to resolve, malformed JSON) satisfies a loose assertion, so the test stays green even when the logic under test is fully broken — this actually happened. Hook output is ASCII-escaped JSON, so Chinese reasons appear as `\uXXXX`; match on ASCII fragments (`Plan gate:`, `.gate_disabled`, `Secret blocked`, `Personal data blocked`, `Invalid Copilot hook input`).

Copilot tests must also pass `cwd` through `cygpath -w` (with backslashes escaped for JSON) on Windows: Git Bash rewrites POSIX paths passed as *arguments* to native binaries, but not content arriving on *stdin*, which is how hook events are delivered.

## Making a change: required checklist

1. Identify the single source of truth for the feature (`shared/claude/`, `shared/codex/`, or — if none exists yet — every duplicated copy) and every published copy/entry point.
2. Build the platform × mode × distribution impact matrix (see `ARCHITECTURE.md` "多版本一致性架構" table).
3. Edit the source of truth, run the sync script, or hand-edit every duplicated copy plus add/extend a byte-for-byte or behavioral parity test.
4. Run the relevant mode-specific tests, then `bash tests/run_all.sh` (smoke); use
   `AGK_TEST_PROFILE=full bash tests/run_all.sh` when complete mode-switch coverage is required.
5. Update `README.md` / `CLI_REFERENCE.md` / `ARCHITECTURE.md` / `CHANGELOG.md` if the change affects public interface or behavior; bump `claude/plugins/<mode>/.claude-plugin/plugin.json` `version` if that mode's Claude plugin behavior changed. Codex/Copilot have no version field — never invent one (see `VERSIONING.md`).
6. State explicitly in your final report which platform/mode/distribution combos were changed, which were checked-but-not-applicable (and why), and what tests were run.

Release coordinate is a repo `git tag vX.Y.Z` (see `VERSIONING.md`), not per-plugin versions — `main` is protected, so releases land via a CHANGELOG-only PR, then a tag pushed after merge.
