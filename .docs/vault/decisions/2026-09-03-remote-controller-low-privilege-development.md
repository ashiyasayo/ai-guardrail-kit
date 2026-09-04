# Remote controller 的低權限開發流程

日期：2026-09-03

## 背景

Claude Code 與 Codex 的 remote controller 用戶端可能無法執行 `!` 命令，或無法呈現
平台原生 `ask` 核准 UI。既有 strict 流程依賴本機終端機核准或逐次原生核准，因此手機
用戶端不能安全地完成 strict 授權。

## 決策

目前不新增會自動放寬 strict 的 `remote` 模式，也不接受提示詞、模型可寫入的旗標或
模型可修改的政策檔作為遠端核准證據。

在未實作可信任手機核准通道前，遠端開發採預先設定的低權限流程：

1. 人類先在可信任桌機為**個別專案**選擇模式與政策；不得以個人層級政策放寬所有專案。
2. Claude Code 使用 `integrated-harness` 的 `standard`：保留拆解與允許修改範圍，免除
   strict 的人工核准。
3. Codex 使用 `integrated-harness` 的 `light`，只允許已建立計畫後、範圍內的
   `apply_patch`；`exec_command` 仍須原生 `ask`，不屬手機流程。
4. 遠端工作只在無正式憑證、無部署權限的 branch 進行；測試、建置與外部副作用移交
   GitHub Actions 或可信任桌機。
5. 所有變更經 PR 與 CI 驗證後，由人類以 GitHub 的既有身分驗證介面審查／合併。

此流程是降低遠端寫入權限的操作安排，不能等同 strict 核准，且不改變既有四種產品模式。

## 未來實作門檻

若要讓手機直接核准 strict，應建立外部、可驗證的簽章核准通道。核准證明至少必須綁定：

- 經驗證的人類身分與專案；
- repository、branch／commit、mode 與拆解文件 SHA-256；
- 允許修改路徑與允許的操作種類；
- 短 TTL、一次性 nonce 與可稽核紀錄。

Hook 應只驗證人類核准服務簽發的證明，並以公開金鑰離線驗證簽章；模型不可產生、延長或
重放該證明。需要撤銷時，應採短 TTL 加上受控的撤銷資料，而非讓 hook 熱路徑無條件連網。

實作前需另行設計 token 格式、金鑰輪替、遺失裝置處理、GitHub／企業身分整合、跨平台
hook 契約，以及 Claude、Codex、Copilot 的行為一致性測試。
