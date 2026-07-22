# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- `pii_patterns.py`（`harness`／`integrated-harness` 共用）將 `RULES` 契約由三元組
  升級為四元組（名稱、regex、遮罩函式、**驗證函式**）；命中判定改為「regex 命中
  且驗證函式為 `None` 或回傳 `True`」，讓需要額外邏輯的規則也能納入而不放寬 regex。
  兩個 consumer（`redact_sensitive_info.py`、`block_pii_prompt.py`）同步調整驗證邏輯，
  四個位置維持逐字元相同。
  - 信用卡卡號：放寬為 13–19 碼（含連續無分隔），改以 **Luhn checksum** 驗證過濾
    一般長數字（如訂單編號）誤判，取代原本僅限 4-4-4-4 分隔格式的做法。
  - 新增「學號」「護照號碼」規則，採「標籤錨定」（需鄰近出現 `學號`／`護照`／
    `student id`／`passport` 等標籤才觸發），降低與身分證字號、任意編號的誤判；
    屬精確率優先取捨，無法涵蓋無標籤裸資料。
  - `harness` plugin 版號由 0.4.0 升級為 0.5.0，`integrated-harness` 由 0.3.0
    升級為 0.4.0。
  - 註：Codex 平台有各自獨立的 `shared/codex/pii_patterns.py`，本次尚未同步擴充。

### Security

- Codex 秘密檢查同步補上 Bash `${VAR:-fallback}` 與未加引號憑證指派判定，
  可區分環境變數 fallback 與硬編碼秘密值。

- Codex `integrated-harness` 的 `SessionStart` 提醒同步支援讀取 plugin 內的
  `reasoning-protocol.md`；文件不存在、無法讀取或非 UTF-8 時安全回落基本提醒。

- Codex `harness`／`integrated-harness` 危險命令檢查同步加入 shell token 化判定，
  補強受保護分支 force-push、`curl|shell` 下載即執行、`find -exec` 間接寫入、
  命令替換與多種旗標排列的攔截，並保留原有 regex fallback。

- Codex `decomposition-gate` 同步加入 `.codex/guardrail/plan/.gate_disabled` 緊急逃生口；
  只有人類可預先建立，Codex 工具與 `exec_command` 不得自建或修改，並新增對應回歸案例。

- `decomposition-gate` 補上逃生口保護：`.claude/plan/.gate_disabled` 只能由人類在
  自己的終端機建立，模型透過寫入工具或 Bash 自建一律 deny（比照 `plan_gate.py`
  對 `.plan_approved` 的既有保護），避免模型自我停用拆解閘門。`decomposition-gate`
  plugin 版號由 0.1.2 升級為 0.2.0。

### Changed

- Codex 驗證腳本沿用共用的 Python 直譯器回退結果，不再在 Windows 只有 `python`
  時錯誤要求 `python3`。

- Codex 模式切換流程只在啟動時探測一次可用的 Python 直譯器，避免每個 hook
  命令產生時重複啟動子程序進行版本探測。

- Codex 模式切換在非互動式背景程序中重設繼承的 `SIGINT` 忽略狀態，確保中斷時能執行
  rollback，並保留原始退出碼。

- 文件釐清：`integrated-harness` README 明確說明 `light` 模式不解析也不強制
  `## 允許修改範圍`（等同放棄檔案範圍管制，只保留「有拆解才能動」）；個資防護
  機制文件同步更新規則種類、Luhn 與標籤錨定的判斷方式與已知限制。

### Changed

- 六份 `settings.json`／`hooks.json`（`decomposition-gate`、`harness`、
  `integrated-harness` 各自的 copy-in 與 marketplace 版）的直譯器探測指令：
  `python3`／`python`／`py` 皆不可用時，改為先在 stderr 印出清楚訊息（提示
  安裝 Python 3.9+ 並加入 PATH）再 `exit 127`，取代原本完全無訊息的失敗；
  exit code 語意未變。根目錄 `README.md`「需求環境」段落同步說明 Python
  是唯一執行期依賴、無任何 `pip` 套件需求。
- `tests/codex_marketplace_test.sh` 的版號比對比照 `claude_marketplace_test.sh`
  的既有修法，改為驗證 semver 格式而非寫死特定版號（原本仍卡在
  `integrated-harness` 舊版號 `0.1.2`，每次版號升級都會過期失敗）。

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
