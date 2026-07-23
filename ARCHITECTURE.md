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

規則引擎只使用 Python 標準函式庫。Codex 的共用可稽核來源位於
`shared/codex/`，發佈 plugin 保留可攜副本，並由
`scripts/sync-codex-hook-copies` 檢查同步。平台 hook 協定不同，但敏感資料
規則與產品邊界保持對等。

## 安全邊界

此模式是送模／寫入前的規則式防線，不是完整 DLP、惡意軟體掃描器或附件
OCR 引擎。二進位附件與影像內容的抽取、OCR、檔案型別驗證及隔離，仍屬後續
`scan-and-redact` 附件掃描層的範圍。
