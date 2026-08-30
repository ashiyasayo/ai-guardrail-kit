# Architecture

## 模式邊界

| 模式 | 流程拆解 | 敏感資料 | 危險命令 | 人類核准 | 治理政策 |
| --- | --- | --- | --- | --- | --- |
| `decomposition-gate` | 有 | 無 | 無 | 無 | 無 |
| `sensitive-data-guard` | 無 | 有 | 無 | 無 | 無 |
| `harness` | 無 | 有 | 有 | 有 | 無 |
| `integrated-harness` | 有 | 有 | 有 | 有 | 精簡治理政策 |

四種模式是互斥的產品邊界，不是可任意疊加的 feature flags。Claude selector 會管理
其平台的模式安裝；Codex selector 只釘住每專案 runtime，不 add/remove mode plugin。
Copilot 為 copy-in、
無 selector，互斥性由安裝者負責：兩個 Copilot 模式都註冊 `PreToolUse` 且都含
`hook_protocol.py`，同時複製進 `.github/hooks/` 會衝突。

Claude `decomposition-gate` 的 copy-in 與 marketplace 發佈皆由 SessionStart 載入
同一份風險分級協定；同步測試守護主協定、subagent 協定及注入 hook。Codex
`integrated-harness` 則由 plugin skill 提供對等的執行行為校準。

Claude selector／verifier 支援 `project`、`local`、`user` 三種 scope；其中
`user` 會讓 plugin 對該使用者的所有 Claude Code 專案生效。若改用 Claude
原生 CLI 從遠端 marketplace 安裝 user scope，則不經本專案的 package
validation、互斥及 rollback 邊界。

Codex CLI 的 plugin 安裝狀態是使用者層級，但本專案只安裝
`ai-guardrail-loader@ai-guardrail-kit`。selector 檔分別是
`<project>/.codex/guardrail/runtime.json`、`runtime.local.json` 與
`$CODEX_HOME/guardrail/default-runtime.json`，precedence 為
local > project > user。loader 從 event cwd 找 root，離線解析完整 cache identity，
再以固定 Python argv 執行 verified entrypoint；global integrated-harness installer
只是 user fallback 相容 wrapper。

## Codex runtime manager data flow

`codex-runtime-manager` 將 `resolve`、`prepare`、`commit`、`verify` 與 `dispatch` 收在
單一深 module。HTTPS manifest source 嚴格限制 origin、redirect hop、timeout 與下載大小；
archive 先驗 SHA-256，再拒絕 traversal、drive/UNC、symlink、hardlink、device、FIFO、
duplicate normalized path 與解壓炸彈。cache metadata 同時保存 selector identity 與
每個 payload file digest，hook 每次重新驗證 metadata、完整 payload、entrypoint regular
file 及 containment。

全域 hooks 只指向 `$CODEX_HOME/guardrail/loader/loader.py`，以 slot 保留
decomposition／plan／security／PII／SessionStart 的順序與獨立決策；子程序固定
`[python, "--", verified_entrypoint]`、`shell=False`，不傳下載憑證且不在 hook 熱路徑連網。
selector commit 同步維護 `$CODEX_HOME/guardrail/selector-index.json`，讓低頻 prune
能在刪除前重建引用集合；prune 預設 dry-run，只有明確 `--apply` 才刪除已重新驗證、
超過 grace period 且未被 selector 引用的 digest cache。

## 多版本一致性架構

每次功能變更都必須以「平台 × 模式 × 發佈型態」盤點影響範圍；根目錄
`AGENTS.md` 定義代理的施作與交付義務，本節記錄各版本的結構關係，CI 測試負責
確定性阻止副本漂移。檔案名稱或實作語言不同不代表行為契約不同。

| 平台 | 模式 | 發佈型態 | 主要來源或入口 | 一致性保障 |
| --- | --- | --- | --- | --- |
| Claude | `decomposition-gate` | copy-in、marketplace | `decomposition-gate/.claude/`、`claude/plugins/decomposition-gate/` | 協定與注入 hook 逐位元組比對、marketplace 結構測試、smoke test |
| Claude | `sensitive-data-guard` | marketplace | `shared/claude/`、`claude/plugins/sensitive-data-guard/` | shared 同步檢查及 PII 行為測試 |
| Claude | `harness` | copy-in、marketplace | `shared/claude/`、`harness/.claude/`、`claude/plugins/harness/` | shared 同步、copy-in parity 及 hook 行為測試 |
| Claude | `integrated-harness` | copy-in、marketplace | `shared/claude/`、`integrated-harness/`、`claude/plugins/integrated-harness/` | 協定同步、copy-in parity、orchestration 與 hook 行為測試 |
| Claude | 四種模式 | marketplace／selector（project、local、user） | `shared/claude/`、`claude/plugins/`、`scripts/claude-mode-lib.sh` | shared 同步、marketplace、三 scope mode switch 及 guardrail 測試 |
| Claude | 四種模式 | native user fallback | Claude 原生 `plugin install --scope user`；不經 repository selector | marketplace 文件與 CLI 操作契約測試 |
| Codex | 四種模式 | runtime archive／selector（project、local、user） | `shared/codex/`、`codex/plugins/`、`scripts/codex-runtime-manager.py` | manifest/archive/cache、A/B scope、offline、rollback 測試 |
| Codex | loader | marketplace／global install | `codex/plugins/ai-guardrail-loader/`、`$CODEX_HOME/guardrail/` | loader bootstrap、hook slot、plugin-id 與 rollback 測試 |
| Codex | `integrated-harness` | global compatibility wrapper | `scripts/install-codex-global-integrated-harness`、user selector | policy 不覆寫、legacy marker 遷移測試 |
| Copilot | `decomposition-gate` | copy-in | `shared/copilot/`、`copilot/plugins/decomposition-gate/` | shared 同步檢查、Copilot smoke test；Preview 平台限制另見相關文件 |
| Copilot | `sensitive-data-guard` | copy-in | `shared/copilot/`、`copilot/plugins/sensitive-data-guard/` | shared 同步檢查、三平台 PII 行為一致性測試、Copilot smoke test |

若某次變更對矩陣中的版本不適用，交付說明必須列出該版本及原因。已有 `shared/`
單一事實來源的功能一律先改來源再同步；無法共用檔案者以共同測試語料驗證行為，
不得依靠人工記憶維持一致。

根層 `tests/run_all.sh` 預設執行快速 `smoke` profile，保留共享同步、marketplace、
guardrail 及 global install 等日常回歸；Claude 與 Codex 的完整模式切換測試改由
`AGK_TEST_PROFILE=full` 手動執行，或由 CI 的排程／手動 workflow 執行。這是測試執行
策略的分層，不代表矩陣中的模式或發佈型態被移除。

`integrated-harness` 的 `ORCHESTRATOR.md` 不負責教導一般任務分解、模型路由或
代理調度；這些工作交由平台與模型。文件只保留人類授權、外部副作用、修改範圍、
驗收證據、成本與失敗揭露。`harness/fable-orchestrator-prompt.md` 是 deprecated
相容資產，不再是產品功能或建議工作流程。

Claude `integrated-harness` 的執行行為校準位於 `reasoning-protocol.md` 與
`reasoning-protocol-subagent.md`，由 SessionStart hook 注入。它依工作風險控制
播報、對抗式審查、信心標示、驗證深度及 subagent 委派；治理授權仍只由
`ORCHESTRATOR.md`、政策檔與確定性 hooks 決定。copy-in 與 marketplace 版本的兩份
協定必須逐字節一致。

## sensitive-data-guard 資料流

Claude 的 `PreToolUse` dispatcher 先執行秘密檢查，再執行個資遮罩；
`UserPromptSubmit` 負責在提示送模前攔截個資。Codex 將秘密檢查與個資檢查
註冊為 hooks：`exec_command`／`apply_patch` 先做秘密檢查，`apply_patch`
另做個資遮罩，`UserPromptSubmit` 則攔截提示詞個資。

Copilot 的 `PreToolUse` 依序執行秘密檢查與個資檢查，任一命中即 deny；
`UserPromptSubmit` 只檢查個資。**Copilot 的個資採 deny 而非遮罩改寫**——遮罩依賴的
`updatedInput` 在 VS Code 上未經實機驗證，失效時會退化成「allow 未遮罩的原始內容」，
屬安全控制無聲失效；deny 沒有這種失敗模式。Copilot 另以遞迴掃描整個 `tool_input`
取代欄位名對應，並將 `run_in_terminal` 納入個資涵蓋範圍（Claude 版的遮罩刻意排除
Bash，因改寫指令字串會破壞語法；deny 無此問題）。這三項為刻意的平台差異，
記錄於 `.docs/vault/decisions/2026-07-31-copilot-sensitive-data-guard.md`。

規則引擎只使用 Python 標準函式庫。三平台的 PII 規則各有唯一審核來源：Claude
位於 `shared/claude/`（PII 三件組），Codex 位於 `shared/codex/`，Copilot 位於
`shared/copilot/`；發佈的 plugin 與 copy-in 保留可攜副本，分別由
`scripts/sync-claude-hook-copies`、`scripts/sync-codex-hook-copies` 與
`scripts/sync-copilot-hook-copies` 檢查同步。三份來源的規則行為由
`tests/pii_cross_platform_parity_test.sh` 以共同語料守護（命中種類與遮罩輸出須完全
一致），不依靠人工記憶維持。平台 hook 協定不同，但敏感資料規則保持對等；
產品邊界則有上述刻意差異。

## 安全邊界

此模式是送模／寫入前的規則式防線，不是完整 DLP、惡意軟體掃描器或附件
OCR 引擎。二進位附件與影像內容的抽取、OCR、檔案型別驗證及隔離，仍屬後續
`scan-and-redact` 附件掃描層的範圍。

## 版號載體的不對稱

三個平台的 plugin 格式不同，能承載版號的欄位也不同——這是結構事實，不是疏漏：

| 平台 | 版號載體 |
| --- | --- |
| Claude Code | `claude/plugins/<mode>/.claude-plugin/plugin.json` 的 `version`（平台介面欄位） |
| Codex | 無（plugin 目錄僅 `hooks/`、`skills/` 等內容） |
| GitHub Copilot | 無（設定為 `.github/hooks/*.json`，格式無版號欄位） |

因此發布座標統一為 **repo 的 Git tag**，而非 per-plugin 版號；本專案刻意不為
Codex／Copilot 另建版號檔案，以免產生無平台讀取、無機制同步的第二套真相來源。
語意與發版流程見 [`VERSIONING.md`](VERSIONING.md)。

## GitHub Copilot (VS Code) 平台移植（Preview，部分）

第三平台目前移植兩個模式：`decomposition-gate` 與 `sensitive-data-guard`，
分別位於 `copilot/plugins/` 下同名目錄；與 Claude／Codex 共用同一套思考協定與
偵測規則，平台接線不同，`sensitive-data-guard` 另有三項刻意的產品行為差異
（見上方「sensitive-data-guard 資料流」）。

- **執行模型**：VS Code Agent hooks（Preview）的 `PreToolUse`（`sensitive-data-guard`
  另含 `UserPromptSubmit`）→ 平台薄啟動器（`launch.ps1`／`launch.sh`）→ 單一 Python
  邏輯。來源佈局＝部署佈局：`hooks/` 整包複製到目標 repo 的 `.github/hooks/`。
- **共用來源**：`hook_protocol.py` 與 `pii_patterns.py` 以 `shared/copilot/` 為唯一
  審核來源，由 `scripts/sync-copilot-hook-copies` 同步。**啟動器刻意不共用**：
  Windows 啟動器是 Copilot 移植風險最高的產物，且兩模式互斥安裝、永不共存，
  跨模式分歧沒有執行期交互風險；`sensitive-data-guard` 的啟動器為參數化版本
  （兩個進入點、錯誤路徑的 `hookEventName` 依事件而異）。
- **管制向量**：`create_file`、`multi_replace_string_in_file`（依本質），以及
  `run_in_terminal`（**整體 gate**——shell 語法無法證明無寫入，比照 Codex `exec_command`；
  spike 證明對抗性 agent 會用終端機繞過寫入意圖正則）。唯讀與未知工具放行。
- **拆解產出物**：`.github/guardrail/plan/decomposition.md`；逃生口 `.gate_disabled` 同目錄。
- **平台約束（Phase 0 spike 實證）**：設定用 `.github/hooks/*.json` 扁平格式 + 分平台鍵 +
  **工作區相對路徑**（`${workspaceFolder}` 不可用，與 PowerShell `${var}` 語法衝突）；
  入站讀原始位元組解 UTF-8、出站 ASCII-safe JSON；**VS Code 對 hook 錯誤／非 JSON 輸出
  fail-open**，故啟動器對任何錯誤自印 deny。
- **fail-closed 的可恢復性邊界**：`sensitive-data-guard` 的 `UserPromptSubmit` 刻意只
  驗證最小欄位集（`hook_event_name`、`prompt`）。PreToolUse 擋一次工具呼叫是可恢復的；
  UserPromptSubmit 若因欄位驗證過嚴而擋掉所有提示，使用者連排除問題的提示都送不出去，
  屬不可恢復的鎖死。fail-closed 的代價必須可恢復。
- **狀態**：Windows 主線已實機驗證，macOS／Linux 附帶未驗；僅 Copilot Agent mode 生效。
  `sensitive-data-guard` 的 `UserPromptSubmit` 阻擋輸出形狀尚未實機驗證，該道防線在
  驗證前不可宣稱有效；`send_to_terminal` 未納入涵蓋範圍。決策與踩坑見 `.docs/vault/`。
