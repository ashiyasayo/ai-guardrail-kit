# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- `integrated-harness` 新增個資保護兩層防線（僅 Claude Code 平台）：
  - `redact_sensitive_info.py`（PreToolUse，掛載於 `guard.py`）：偵測寫入內容中
    疑似台灣身分證字號、手機號碼、Email，去識別化改寫後放行（非阻擋）。
  - `block_pii_prompt.py`（UserPromptSubmit）：使用者提交提示當下偵測疑似個資，
    整段阻擋並提示改以去識別化內容重新送出；因 Claude Code 的 UserPromptSubmit
    不支援改寫提示內容，僅能阻擋，與 PreToolUse 的去識別化互補為縱深防禦。
  - `integrated-harness` plugin 版號隨此變更由 0.1.5 升級為 0.2.0。

### Changed

- 統一 `harness`／`decomposition-gate` 的最低 Python 版本需求為 3.9+（原為
  3.8+），與 `integrated-harness` 及 Codex 三種模式一致，避免版本需求混淆。

### Added

- Codex `integrated-harness` can now be installed once as a global default with
  `scripts/install-codex-global-integrated-harness`.
- Global Codex hooks are merged into `~/.codex/hooks.json` without removing
  unrelated hooks; removal restores the pre-install hooks file.
- The global plan gate defers only while a project has no decomposition plan;
  once a plan exists, normal integrated-harness scope, policy, and approval
  checks apply.