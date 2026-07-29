# Architecture

## 模式邊界

| 模式 | 流程拆解 | 敏感資料 | 危險命令 | 人類核准 | 治理政策 |
| --- | --- | --- | --- | --- | --- |
| `decomposition-gate` | 有 | 無 | 無 | 無 | 無 |
| `sensitive-data-guard` | 無 | 有 | 無 | 無 | 無 |
| `harness` | 無 | 有 | 有 | 有 | 無 |
| `integrated-harness` | 有 | 有 | 有 | 有 | 精簡治理政策 |

四種模式是互斥的產品邊界，不是可任意疊加的 feature flags。Claude 與
Codex selector 會移除其他受管模式，再安裝並驗證目標模式。

Claude `decomposition-gate` 的 copy-in 與 marketplace 發佈皆由 SessionStart 載入
同一份風險分級協定；同步測試守護主協定、subagent 協定及注入 hook。Codex
`integrated-harness` 則由 plugin skill 提供對等的執行行為校準。

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
| Codex | 四種模式 | marketplace／selector | `shared/codex/`、`codex/plugins/`、`scripts/codex-mode-lib.sh` | shared 同步、marketplace、mode switch 及 guardrail 測試 |
| Codex | `integrated-harness` | global install | `codex/plugins/integrated-harness/`、global installer | global install 交易與 rollback 測試 |
| Copilot | `decomposition-gate` | copy-in | `copilot/plugins/decomposition-gate/` | Copilot smoke test；Preview 平台限制另見相關文件 |

若某次變更對矩陣中的版本不適用，交付說明必須列出該版本及原因。已有 `shared/`
單一事實來源的功能一律先改來源再同步；無法共用檔案者以共同測試語料驗證行為，
不得依靠人工記憶維持一致。

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

規則引擎只使用 Python 標準函式庫。兩平台的 PII 規則各有唯一審核來源：Claude
位於 `shared/claude/`（PII 三件組），Codex 位於 `shared/codex/`；發佈的 plugin
與 copy-in 保留可攜副本，分別由 `scripts/sync-claude-hook-copies` 與
`scripts/sync-codex-hook-copies` 檢查同步。平台 hook 協定不同，但敏感資料
規則與產品邊界保持對等。

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

第三平台移植的第一個模式為 `decomposition-gate`，位於
`copilot/plugins/decomposition-gate/`；與 Claude／Codex 共用同一套思考協定，僅平台接線不同。

- **執行模型**：VS Code Agent hooks（Preview）的 `PreToolUse` → 平台薄啟動器
  （`launch.ps1`／`launch.sh`）→ 單一 Python 邏輯（`decomposition_gate.py` +
  `hook_protocol.py`）。來源佈局＝部署佈局：`hooks/` 整包複製到目標 repo 的 `.github/hooks/`。
- **管制向量**：`create_file`、`multi_replace_string_in_file`（依本質），以及
  `run_in_terminal`（**整體 gate**——shell 語法無法證明無寫入，比照 Codex `exec_command`；
  spike 證明對抗性 agent 會用終端機繞過寫入意圖正則）。唯讀與未知工具放行。
- **拆解產出物**：`.github/guardrail/plan/decomposition.md`；逃生口 `.gate_disabled` 同目錄。
- **平台約束（Phase 0 spike 實證）**：設定用 `.github/hooks/*.json` 扁平格式 + 分平台鍵 +
  **工作區相對路徑**（`${workspaceFolder}` 不可用，與 PowerShell `${var}` 語法衝突）；
  入站讀原始位元組解 UTF-8、出站 ASCII-safe JSON；**VS Code 對 hook 錯誤／非 JSON 輸出
  fail-open**，故啟動器對任何錯誤自印 deny。
- **狀態**：Windows 主線已實機驗證，macOS／Linux 附帶未驗；僅 Copilot Agent mode 生效。
  決策與踩坑見 `.docs/vault/`。
