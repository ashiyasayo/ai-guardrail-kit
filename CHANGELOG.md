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
- `harness` 補上 `block_pii_prompt.py`（UserPromptSubmit）阻擋型個資防線；
  規則抽成共用的 `pii_patterns.py`，與 `integrated-harness` 逐字元同步，
  避免兩份規則各自維護漂移。plugin 版號由 0.1.3 升級為 0.2.0。
- `harness` 的 `guard.py` 升級為 `hookSpecificOutput` JSON 傳遞協定（deny 語意
  不變，只換傳遞機制，比照 `integrated-harness`；三支既有檢查 hook 的
  `check()` 回傳值未變）；並補上 `redact_sensitive_info.py`（PreToolUse，
  與 `integrated-harness` 逐字元相同），寫入類工具偵測到疑似個資時自動
  去識別化改寫後放行，補齊 `harness/MAINTENANCE.md` 原先記錄的能力落差。
  plugin 版號由 0.2.0 升級為 0.3.0。
- `pii_patterns.py`（`harness`／`integrated-harness` 共用單一事實來源）擴充個資
  規則種類，新增「地址」（台灣縣市＋路街＋門牌格式）與「信用卡卡號」（限
  4-4-4-4 分隔格式，降低誤判）；學號、護照號碼因與既有規則格式高度重疊或
  缺乏可辨識結構、易誤判，刻意不納入，詳見兩個目錄 `MAINTENANCE.md` 的說明。
  `harness` plugin 版號由 0.3.0 升級為 0.4.0，`integrated-harness` 由 0.2.0
  升級為 0.3.0。

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