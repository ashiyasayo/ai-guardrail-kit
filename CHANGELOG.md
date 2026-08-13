# Changelog

All notable changes to this project are documented in this file.

版本語意、各平台版號載體差異與發版流程見 [`VERSIONING.md`](VERSIONING.md)。
發布座標是 Git tag `vX.Y.Z`；Claude plugin 的 `plugin.json` 版號是該模式自身的
行為版本，不等於 repo 版本。

## [Unreleased]

### Fixed

- Codex `decomposition-gate` 與 `integrated-harness` 明確以 UTF-8 讀取計畫及治理政策檔，
  避免 Windows 未啟用 UTF-8 mode 時，含繁體中文的有效計畫被誤判為不存在或無法讀取。

### Changed

- README 與 CLI reference 補充 Codex／Claude Code 的互動命令模式：可在輸入列以 `!`
  直接執行 shell 命令，無須離開目前 thread／session 或另開終端機。
- `tests/run_all.sh` 預設改跑快速 `smoke` profile，略過耗時的 Claude／Codex 完整模式切換
  測試；可用 `AGK_TEST_PROFILE=full` 手動執行，CI 也提供手動與每週排程的完整回歸入口。
- Codex 完整模式切換測試在 Windows Git Bash 缺少 `shasum` 時改用 `sha256sum` fallback，
  避免完整回歸在測試初始化階段失敗。
- Codex selector／verify 合併重複的 Python 啟動：一次同一台 Windows 主機的單支專測由
  1,004 秒降至 955 秒，節省約 4.9%；完整回歸時間仍會受主機 I/O 波動影響。
- Codex selector 將驗證改為共用 Bash 流程，並以 `awk` 執行 ASCII 設定分隔符檢查，
  避免另開 verify 子程序及不必要的 Python 啟動；同一台 Windows 主機的專測由
  955 秒降至約 652 秒，節省約 32%。完整模式轉換、rollback 與訊號測試覆蓋維持不變。

## [0.3.0] - 2026-08-11

### Added

- GitHub Copilot (VS Code) 新增第二個模式 `sensitive-data-guard`（實驗性，Preview），
  提供明文憑證阻擋、待寫入內容個資阻擋與提示詞個資阻擋，涵蓋 `PreToolUse` 與
  `UserPromptSubmit` 兩個事件。與 Claude／Codex 版有三項**刻意的產品行為差異**：
  ① 個資採 deny 而非遮罩改寫——Claude／Codex 依賴的 `updatedInput` 改寫機制在
  VS Code 上未經實機驗證，若失效會退化成「allow 未遮罩的原始內容」，屬安全控制
  無聲失效；② 個資與憑證都掃描 `run_in_terminal`（Claude 版刻意不掃 Bash），
  因 spike 實測 agent 會用終端機繞過檔案寫入的 deny；③ 不依賴工具名白名單，
  改為遞迴掃描整個 `tool_input` 的所有字串值，避免猜錯欄位名導致靜默放行。
  **已知限制**：`UserPromptSubmit` 的阻擋輸出形狀尚未實機驗證，該道防線在驗證前
  不可宣稱有效；`send_to_terminal` 未納入涵蓋範圍。兩個 Copilot 模式互斥，
  不得同時安裝。

- 新增 `shared/copilot/` 作為 Copilot 端 hook 的唯一審核來源（`hook_protocol.py`、
  `pii_patterns.py`）與同步腳本 `scripts/sync-copilot-hook-copies`；新增
  `tests/copilot_shared_sync_test.sh` 守護副本無漂移。另新增
  `tests/pii_cross_platform_parity_test.sh`，以共同語料驗證 Claude、Codex、Copilot
  三份 PII 規則的命中種類與遮罩輸出完全一致，避免第三份副本造成規則漂移。
  Copilot 的 hook 測試首次納入根層 `tests/run_all.sh` 回歸範圍。

### Changed

- Copilot `hook_protocol.py` 擴充為支援 `PreToolUse` 與 `UserPromptSubmit` 兩個事件，
  並改由 `shared/copilot/` 同步到兩個模式。擴充為純附加（`load_event` 的
  `expected_event` 預設為 `PreToolUse`），`decomposition-gate` 的行為不變，
  由其既有 16 情境 smoke test 把關。啟動器（`launch.ps1`／`launch.sh`）刻意不納入
  共用：Windows 啟動器是 Copilot 移植風險最高的產物，且兩模式互斥安裝、
  永不共存，跨模式分歧沒有執行期交互風險。
- 重新修正 README「四種模式總覽」的一句話定位，明確區分流程紀律、資料保護、
  授權安全與完整治理四個產品邊界。

## [0.2.1] - 2026-07-29

### Fixed

- Claude `integrated-harness` 的計畫閘門（`plan_gate.py`）在 strict 模式核准失敗時，
  deny 訊息內嵌字面文字 `${CLAUDE_PLUGIN_ROOT}`，要求人類在自己的終端機貼上執行；
  該環境變數只在 Claude Code 內部工具執行環境展開，人類自己開的終端機沒有這個變數，
  貼上執行會展開成空字串，導致 `approve_plan.py` 的路徑退化成無效目錄、無法核准
  計畫。改為以 `__file__` 動態算出 `approve_plan.py` 的絕對路徑，讓訊息中的指令可
  直接複製貼上執行；`orchestration-policy.md` 範本說明與相關 parity 測試同步更新。
  Claude `integrated-harness` plugin 版號由 0.6.0 升為 0.6.1。

## [0.2.0] - 2026-07-29

### Added

- 新增根目錄 `AGENTS.md`，將每次變更必須盤點並同步所有平台、模式與發佈型態
  設為專案級代理規則；`ARCHITECTURE.md` 新增多版本來源、入口與一致性保障矩陣，
  並以 vault 決策記錄規則、架構文件及 CI 測試三層契約。此項只改變專案維護流程，
  不改變 plugin 執行行為或版號。

### Changed

- Claude `decomposition-gate` 的 copy-in 與 marketplace 推理協定同步改為相同的
  風險分級規則，移除每次固定三方案、兩次反駁及信心標示；新增 SessionStart hook，
  修正 marketplace 雖打包協定卻未實際載入的缺口。Claude plugin 版號由 0.2.0
  升為 0.3.0。Codex `integrated-harness` skill 亦加入相同的精簡播報、低委派與
  風險相稱驗證規則；deprecated 的歷史 Fable 提示稿明確標示不會被執行流程載入。

- Claude `integrated-harness` 的 SessionStart 推理協定改為風險分級：進度只在重要
  發現、阻礙或方向改變時更新；一般與機械性工作不再強制對抗式審查或信心標示；
  subagent 僅用於具一定規模且可真正獨立並行的工作，不再用於小型任務或單純複核；
  並避免沒有新證據的重複檢查。copy-in 與 marketplace 協定同步更新，治理授權與
  確定性 hooks 行為不變。Claude `integrated-harness` plugin 版號由 0.5.0 升為 0.6.0。

## [0.1.0] - 2026-07-27

首個標記版本。`0.x` 表示 Preview，不承諾相容性——Copilot 側依賴仍為 Preview 的
VS Code Agent hooks，且 macOS／Linux 路徑尚未實機驗證。以下彙整此標記點之前的
全部變更。

> 本節部分條目為 Codex／Copilot 的 plugin 敘述過版號，但這兩個平台的 plugin
> 格式並無版號欄位，那些數字沒有檔案承載、不具查證性。條目作為歷史記錄保留，
> 自本版起不再為 Codex／Copilot 宣稱版號（見 `VERSIONING.md`）。

### Added

- 新增 **GitHub Copilot (VS Code)** 平台的第一個護欄模式 `decomposition-gate`
  （初始版號 `0.1.0`），發行樹 `copilot/plugins/decomposition-gate/`：以 VS Code
  Agent hooks（Preview）的 `PreToolUse` 封鎖寫入向量 `create_file`、
  `multi_replace_string_in_file`、`run_in_terminal`（後者採 Codex 式「拆解前整體
  gate」，因實機 spike 證明對抗性 agent 會用終端機繞過寫入意圖正則），拆解檔
  `.github/guardrail/plan/decomposition.md` 完成前一律 deny；唯讀與未知工具放行。
  單一 Python 邏輯（`decomposition_gate.py` + `hook_protocol.py`）+ 各平台薄啟動器
  （`launch.ps1` Windows 已實機驗證、`launch.sh` POSIX/Mac 附帶標未驗）；設定用扁平
  格式 + 分平台鍵 + **工作區相對路徑**。關鍵約束（皆有 Phase 0 spike 實證）：入站讀
  原始位元組解 UTF-8、出站 ASCII-safe JSON、啟動器對任何錯誤自印 deny（VS Code 對
  hook 錯誤/非 JSON 輸出預設 fail-open）。`tests/smoke_test.sh` 16 情境全通過。
  屬 Preview、僅 Copilot Agent mode 生效；決策與踩坑記於
  `.docs/vault/decisions/2026-07-23-copilot-vscode-support-plan.md` 與
  `.docs/vault/gotchas/2026-07-23-vscode-copilot-hook-wiring.md`。

- 新增 Claude Code 與 Codex 的第四種互斥模式 `sensitive-data-guard`（初始版號
  `0.1.0`）：可獨立安裝明文秘密／憑證阻擋、提示個資阻擋及寫入個資去識別化，
  不包含危險命令、拆解、人工核准或編排；marketplace、selector、verifier 與 Codex
  共用 hook 同步清單一併納入新模式。

- 新增 `scripts/sync-codex-hook-copies` 與對應回歸測試；`shared/codex/` 成為
  Codex 共用 hook 的唯一審核來源，工具可同步或檢查可攜式 plugin 副本的漂移。

- 新增 `shared/claude/` 作為 Claude 側 PII 三件組（`pii_patterns.py`／
  `block_pii_prompt.py`／`redact_sensitive_info.py`）的唯一審核來源，並新增
  `scripts/sync-claude-hook-copies` 與回歸測試 `tests/claude_shared_sync_test.sh`：
  同步腳本以 `cp -p` 產生、以 `cmp -s`（`--check`）守護 5 份發佈副本（3 plugin ＋
  2 copy-in）逐字節一致；Claude 側自此比照 Codex 由單一來源結構性防止漂移，不再
  手動複製。`block_secrets.py`／`block_dangerous_commands.py` 為刻意分歧分支不納入，
  仍由 `tests/claude_hook_parity_test.sh` 行為守護；後者同步移除已被 `--check` 取代的
  逐字節斷言，避免雙軌。

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
  - Codex 平台已於後續移植項目同步相同規則與驗證契約。

- 新增 `tests/claude_copyin_parity_test.sh`：守護 copy-in（`harness/.claude/hooks`、
  `integrated-harness/.claude/hooks`）與 marketplace plugin 的**非 PII** hook
  （`guard.py`／`plan_gate.py`／`block_secrets.py`／`block_dangerous_commands.py`／
  `approve_plan.py`／`inject_protocol.py`）逐字節一致，補上 Layer 1 只覆蓋 PII 三件組
  之外的 copy-in↔plugin 漂移守護缺口。唯一放行 `integrated-harness/plan_gate.py` 的核准
  路徑差異（copy-in 用 `.claude/hooks/`、plugin 用 `${CLAUDE_PLUGIN_ROOT}`），且限定為
  單一連續差異區塊、須涉及 `approve_plan.py`，其餘任何位置差異均判為漂移而失敗。

### Fixed

- 修正 `sensitive-data-guard` plugin 的 PII 三件組各多一個結尾空行、與其餘 4 個位置
  逐字節不一致的漂移（此漂移使 `tests/claude_hook_parity_test.sh` 原為紅燈）；統一對齊
  canonical（106／79／120 行）內容，屬惰性空白差異，偵測與遮罩行為不變。
  `sensitive-data-guard` plugin 版號由 0.1.0 升級為 0.1.1。

- 修正 `sensitive-data-guard`（第四模式）與其他三模式不一致導致的 marketplace 測試紅燈：
  Claude `hooks.json` 兩條命令的 Python 缺失錯誤訊息對齊標準長訊息
  （`tests/claude_marketplace_test.sh`）；Codex `SKILL.md` 補上啟用說明，含
  `scripts/select-codex-mode sensitive-data-guard` selector 指令與新 thread 提示
  （`tests/codex_marketplace_test.sh`）。屬設定一致性修正，hook 攔截行為不變。
  `sensitive-data-guard` plugin 版號再升級：Claude 0.1.1 → 0.1.2、Codex 0.1.0 → 0.1.1。

- 補齊 Codex `decomposition-gate` 遺漏的版號升級：其 `.codex/guardrail/plan/.gate_disabled`
  逃生口功能已具備（manifest 描述亦已載明），但 `.codex-plugin/plugin.json` 版號仍停在
  0.1.2，而 Claude 對應早已為 0.2.0；對齊升級為 0.2.0。

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

- 導入 GitHub Actions CI 與 `main` 分支保護（採 GitHub Flow）：新增
  `.github/workflows/ci.yml`，於 `main` 的 push/PR 執行 `tests/run_all.sh` 與 copilot
  smoke test；`main` 套用 ruleset `main-protection`：禁止直接 push／刪除／force push、
  須經 PR、且 `tests` 狀態檢查通過才能合併。正式版本改以 `git tag` + GitHub Release
  標記（語意化版本）而非獨立分支；Codex marketplace 以 `--ref main` 取得最新穩定、
  或 `--ref <tag>` 釘特定版本，Claude 走預設分支 `main`。決策與演進（含曾短暫評估
  的 release 分支方案）見
  `.docs/vault/decisions/2026-07-27-publishing-and-branch-protection-model.md`。

- 將 `integrated-harness/ORCHESTRATOR.md` 從完整調度教學精簡為治理政策，只保留
  人類授權、外部副作用、修改範圍、驗收證據、成本與失敗揭露；一般任務分解、
  模型選擇及代理調度改由 Claude／Codex 平台自行決定。Claude 的政策範本同步移除
  固定 Opus／Sonnet／Haiku 路由，改為選填禁止模型／供應商與資料區域限制。
- 淘汰 `harness` 產生編排提示稿的主要賣點；`fable-orchestrator-prompt.md` 僅作為
  deprecated 相容資產保留，新專案不再建議使用。Claude／Codex 的 `harness` 版號
  升為 `0.6.0`；Claude `integrated-harness` 升為 `0.5.0`，Codex 升為 `0.6.0`。

- 根目錄 `README.md` 新增 Claude Code／Codex 六種平台模式的完整功能矩陣，涵蓋
  拆解、核准、政策模式、範圍、危險命令、秘密、個資、SessionStart、安裝生命週期、
  維護方式與共同限制；並釐清兩平台核准語意、`light` 範圍行為、附件掃描缺口及
  copy-in 僅適用 Claude。另新增三種模式各自的優點、代價、適用條件、保留必要性，
  以及維持三個 plugin 與合併成單一可設定 plugin 的取捨。同步修正 Claude
  `integrated-harness` 實際支援 `strict`／`standard`／`light` 三種模式的根文件描述。

- Codex 安全判定將巢狀命令、token 化命令、下載管線、regex fallback 與逐行秘密
  判定拆成獨立內部函式；規則優先順序與對外輸出維持不變，降低單一函式複雜度。

- Codex 模式切換的訊號 rollback 回歸測試改為等待 fake CLI 的明確 ready marker，
  取代固定 0.2 秒延遲，避免較慢環境在 trap 安裝前送出訊號造成偶發失敗。

- Codex `harness`／`integrated-harness` 新增 `security_guard.py`，以單一 Python
  程序合併危險命令與秘密寫入兩道純阻擋檢查，減少 `exec_command` 的固定啟動成本；
  兩個 Codex plugin 版號皆升級至 0.4.0。

- 修正 Codex 模式切換快取 Python 直譯器時的命令列參數對應，確保產生的 hook
  指令仍保留實際直譯器與 hook 檔案路徑。

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

- Codex 個資防護同步 Claude 的四元組規則契約、Luhn 信用卡驗證，以及標籤錨定的
  學號與護照號碼規則；`harness`／`integrated-harness` 版號皆升級至 0.5.0。

- `integrated-harness` 最初於 Claude Code 平台新增個資保護兩層防線；Codex 對應
  實作已於本版後續移植項目補齊：
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
  4-4-4-4 分隔格式，降低誤判）；當時學號、護照號碼因與既有規則格式高度重疊或
  缺乏可辨識結構、易誤判而未納入，後續已改採標籤錨定方式補上。
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

[Unreleased]: https://github.com/ashiyasayo/ai-guardrail-kit/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/ashiyasayo/ai-guardrail-kit/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/ashiyasayo/ai-guardrail-kit/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/ashiyasayo/ai-guardrail-kit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ashiyasayo/ai-guardrail-kit/releases/tag/v0.1.0
