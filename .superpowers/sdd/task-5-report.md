# Task 5 implementation report

## Scope

Documented the repository marketplace and actual `codex/` plugin layout,
marketplace registration, mode selection/verification, native `ask` behavior,
approval-disabled boundary, permanent deterministic denials, strict/light
behavior, cachebuster/reinstall flow, new-thread activation, rollback, TOCTOU,
and the separation from Claude semantics.

## TDD evidence

RED:

```text
$ bash tests/codex_marketplace_test.sh
FAIL: docs/codex-marketplace.md must exist
exit 1
```

GREEN:

```text
$ bash tests/codex_marketplace_test.sh
PASS: Codex marketplace and plugin skeletons
exit 0
```

The documentation assertions require the README link, exact marketplace,
selector, and verifier examples, managed config/delimiter warnings, Python 3.9,
new-thread behavior, native approval, direct CLI boundary, cachebuster and TOCTOU
coverage, per-mode selector instructions, and no developer-machine path.

## Full verification

The planned shell suites all exited 0:

- `bash tests/codex_marketplace_test.sh`
- `bash tests/codex_guardrail_test.sh`
- `bash tests/codex_mode_switch_test.sh`
- `bash decomposition-gate/tests/smoke_test.sh` (14 passed, 0 failed)
- `bash integrated-harness/tests/smoke_test.sh` (136 passed, 0 failed)
- `bash integrated-harness/tests/orchestration_test.sh` (0 failed)
- `git diff --check`

The three planned official validator invocations could not start because this
environment lacks PyYAML. Each produced:

```text
ModuleNotFoundError: No module named 'yaml'
```

No validator pass is claimed for those invocations. As a no-install fallback, I
ran the unchanged official `validate_plugin.py` with a temporary YAML shim that
parses the flat scalar frontmatter used by these three skills. All three plugin
validations passed. This exercises the official manifest/path/interface checks
but is supporting evidence, not equivalent to running with PyYAML.

## Review and concerns

The required review confirmed that approval-disabled behavior, deterministic
denial independence, Claude non-equivalence, managed-block ownership, rollback,
and TOCTOU documentation are accurate. It identified these repository-level
gaps, which Task 5 cannot truthfully paper over:

1. `select-codex-mode` has no uninstall operation. Therefore a safe full removal
   through selector tooling cannot be documented. The guide explicitly states
   this and does not invent a command; coordinated manual removal remains a
   reviewed fallback and carries desynchronization risk.
2. The selector skips `codex plugin add` when the target is already installed, so
   it does not itself implement the design's install-or-update promise. The guide
   documents the official cachebuster/direct reinstall followed by selector and
   verifier reconciliation, and marks that sequence non-transactional.
3. The official validator dependency gap remains unresolved without installing
   PyYAML.

The user-facing cachebuster example uses a portable
`<plugin-creator-skill-root>` placeholder rather than a developer-specific
absolute path.

## Blocking product-fix addendum

The manual workaround is superseded by transactional refresh and the exact safe
remove/absence-verification commands. The unexplained plugin-creator placeholder
was removed from user documentation.
