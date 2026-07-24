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

`integrated-harness` 的 `ORCHESTRATOR.md` 不負責教導一般任務分解、模型路由或
代理調度；這些工作交由平台與模型。文件只保留人類授權、外部副作用、修改範圍、
驗收證據、成本與失敗揭露。`harness/fable-orchestrator-prompt.md` 是 deprecated
相容資產，不再是產品功能或建議工作流程。

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
