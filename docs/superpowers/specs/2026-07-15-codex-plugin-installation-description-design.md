# Codex Plugin Installation Description Design

## Goal

Make the full marketplace guide and each Codex plugin's directory description
state the same supported installation workflow.

## Scope

- Update `docs/codex-marketplace.md` with a concise install, verify, and
  new-thread sequence.
- Update the `longDescription` in the three Codex plugin manifests.
- State that `scripts/select-codex-mode` is the supported selector and that
  exactly one managed mode is active for a project.
- State that direct `codex plugin add/remove` is not the supported managed
  workflow.
- In `integrated-harness`, document the project-first policy lookup and the
  optional personal fallback at `~/.codex/guardrail/orchestration-policy.md`.

## Non-goals

- Do not change plugin behavior, installation scripts, marketplace metadata, or
  policy parsing.
- Do not create a personal policy file automatically.

## Verification

Run the existing Codex marketplace test to validate all manifest descriptions
remain valid JSON and preserve the marketplace's structural contract.
