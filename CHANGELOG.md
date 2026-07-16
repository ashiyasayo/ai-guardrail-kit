# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- Codex `integrated-harness` can now be installed once as a global default with
  `scripts/install-codex-global-integrated-harness`.
- Global Codex hooks are merged into `~/.codex/hooks.json` without removing
  unrelated hooks; removal restores the pre-install hooks file.
- The global plan gate defers only while a project has no decomposition plan;
  once a plan exists, normal integrated-harness scope, policy, and approval
  checks apply.