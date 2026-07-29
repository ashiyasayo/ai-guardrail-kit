# Claude 專案規則

1. 主要模型必須載入並遵循 `ORCHESTRATOR.md` 的治理邊界；一般任務分解、模型選擇
   與代理調度交由平台自行決定，subagent 另遵循任務委派與
   `.claude/reasoning-protocol-subagent.md`。
2. 任何修改前，先依 `.claude/orchestration-policy.md` 的 `strict`、`standard` 或
   `light` 建立符合模式的 `.claude/plan/decomposition.md`。一般修改只要求拆解、
   方案與驗證。任務風險決定思考深度；核准模式只決定授權關卡，兩者互不取代。
3. 不得修改 `.claude/orchestration-policy.md` 或建立、更新、刪除核准旗標；
   `approve_plan.py` 只能由人類在自己的終端執行。
4. 資訊不足時明確說明，不得捏造；程式碼識別字使用英文，文件與回覆使用台灣繁體中文。
5. 架構原則：新系統遵循 Clean Architecture、SOLID、TDD／BDD；既有系統從嚴採用
   最小變動原則，不為套用新架構進行非必要改寫（具體適用範圍見
   `.claude/orchestration-policy.md`）。
6. 採用 Spec by Example：需求以具體範例（輸入／預期輸出）表達而非模糊描述，
   範例須可直接轉為可執行的測試案例，作為規格與驗收標準的單一事實來源。
7. 執行與溝通遵循 `.claude/reasoning-protocol.md` 的風險分級：保持進度更新精簡，
   不為一般工作重複驗證，也不為小型或複核工作啟動 subagent。
