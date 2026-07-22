# Orchestration 專案政策

本文件由人類擁有者設定。留空代表沒有預先授權，orchestrator 必須先詢問。
`plan_gate.py` 會比對目前支援檔案工具的政策檔路徑並拒絕修改；非唯讀 Bash 命令直接出現
`.claude` 時會攔截。未知或新增工具必須另行檢查 matcher、tool input／path schema、
permissions 與 hook 支援，不會自動受到同等保護。

政策檔查找順序：專案 `.claude/orchestration-policy.md` 永遠優先；僅在專案檔完全
不存在時，才讀取個人層級 `~/.claude/orchestration-policy.md`。注意：個人層級檔
若設為較寬鬆模式（standard／light），會一併放寬「所有沒有專案政策檔的專案」，
高風險專案請務必建立專案層級政策檔；兩處皆無時一律以 strict 運作。

## 核准模式

- Approval Mode: strict

`strict`：拆解、允許修改範圍與 SHA-256 人工核准。
`standard`：拆解與允許修改範圍，免人工核准。
`light`：基本拆解，免人工核准；只提供思考紀律，不提供授權控制。
缺少本欄位或值無法辨識時，一律視為 `strict`。

`strict` 下由人類執行 `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/approve_plan.py"`（Windows 環境無 `python3` 時改用 `python`）；核准紀錄綁定
目前拆解文件的 SHA-256，有效期間為 60 分鐘。三種模式均不豁免憑證與危險命令 hooks。

下方 allowlist 只允許啟動列出的測試／建置入口；不得包含 pipe、redirect、多命令串接、
command substitution 或環境變數指派前綴。入口內部仍受 permissions、sandbox 與
程式碼審查約束。清單區段內只能放置反引號清單項目，直到下一個 `## ` 標題為止。

## Strict Bash 測試與建置 Allowlist

- `bash tests/`
- `dotnet test`
- `dotnet build`
- `npm test`
- `npm run build`

## 單位與技術堆疊

- 單位情境：<由人類設定；例如所屬部門與其資料敏感度>
- 後端：<由人類設定；語言與框架版本>
- 前端：<由人類設定>
- 資料庫：<由人類設定>
- 基礎設施與交付：<由人類設定；僅供 orchestrator 判斷風險等級與派工邊界，
  不建議在版控中寫出具體廠商或產品名稱>
- 安全與品質：<由人類設定；同上，避免寫出具體資安產品名稱>
- 架構原則：新系統遵循 Clean Architecture、SOLID、TDD／BDD；既有系統從嚴採用
  最小變動原則，不為套用新架構進行非必要改寫；採用 Spec by Example，需求以
  具體範例表達並可直接轉為可執行測試案例。<如有專案特例，由人類補充調整>

允許的目標框架版本、升級規則等專案特定限制：<由人類設定>。
升級目標框架屬計畫範圍變更，未經人類明確核准不得執行。

## 模型對應

`ORCHESTRATOR.md` 的路由規則以能力層級描述，實際模型由人類在此對應。
換平台（例如 Codex、Gemini CLI）時只需改本節，規則正文不動。

- 編排層（orchestrator）：Claude Opus
- 執行層（implementer）：Claude Sonnet
- 輕量層（utility）：Claude Haiku

對應規則：
- 某層未填或該模型不可用時，由能力較高的一層承接；不得向下承接。
- 平台只有單一模型時，三層填同一模型；B 章路由退化為「是否值得分解派工」
  的判斷，其餘章節不受影響。
- 平台以推理強度分級（如 high／medium／low）時，依序對應編排層／執行層／輕量層。

## 成本門檻

- 單一任務最高模型成本：<由人類設定；留空即超出既有計畫時詢問>
- 單一任務最長執行時間：<由人類設定；留空即預期長時間執行時詢問>
- 可自主使用的付費外部資源：<由人類逐項列出；留空即一律詢問>

## 環境授權

- 可自主操作的開發／測試環境：<由人類設定>
- 永遠必須詢問的正式環境：<由人類設定>
