# Integrated Harness

整合 `decomposition-gate` 的結構化拆解、`harness` 的人類核准與安全防線，以及三種
（`strict`／`standard`／`light`）核准模式的編排規則。模式對應的實際模型由
`.claude/orchestration-policy.md` 指定（預設 Claude Opus／Sonnet／Haiku），
可改填其他平台的模型。

## 功能與用途分析

`integrated-harness` 是 `decomposition-gate` 與 `harness` 的整合版，也是三個目錄中唯一同時
具備「編排規則、推理協定、計畫品質檢查、人類授權及安全 hooks」的完整方案。

| 層次 | 解決的問題 | 實作來源 |
| --- | --- | --- |
| 編排層 | 如何分解、選模型、派工、驗收、重試與控制自主權 | `ORCHESTRATOR.md`、政策檔 |
| 思考層 | orchestrator 與 subagent 在行動前應如何分析及自我審查 | `reasoning-protocol*.md` |
| 流程層 | 是否已建立最低合格的拆解文件，是否取得有效人工核准 | `plan_gate.py` |
| 安全層 | 是否疑似寫入憑證，或執行不可交給模型的紅線命令 | `block_secrets.py`、`block_dangerous_commands.py` |
| 個資層 | 使用者提交是否疑似含個資（阻擋）、寫入內容是否疑似含個資（去識別化後放行） | `block_pii_prompt.py`（UserPromptSubmit）、`redact_sensitive_info.py`（PreToolUse） |
| 維護層 | 為何採用各項規則、何時可修改、目前有哪些限制 | `MAINTENANCE.md`、tests |

主要用途是把 AI 開發工作從單純的 prompt 約定，提升為「軟性決策規則＋硬性工具
關卡」：編排文件決定應該怎麼做，hooks 決定尚未滿足條件時不能做什麼。適合多人
協作、高風險資料、正式系統與需要稽核軌跡的專案；若只需要簡單的先拆解後修改，
`decomposition-gate` 會更輕量。

## 三個目錄的定位

| 目錄 | 拆解檢查 | 人類核准 | 安全 Hook | 完整編排層 | 建議用途 |
| --- | --- | --- | --- | --- | --- |
| `decomposition-gate` | 有 | 無 | 無 | 無 | 輕量流程紀律 |
| `harness` | 無 | 有 | 有 | 僅有生成提示稿 | 為既有編排規範補硬性防線 |
| `integrated-harness` | 有 | strict 模式有 | 有 | 有 | 完整部署與後續維護 |

## 組成

- `ORCHESTRATOR.md`：任務分解、模型路由、派工、驗收、授權與反過度設計規則。
- `MAINTENANCE.md`：各章理由、被否決方案、修改時機與已知限制。
- `.claude/reasoning-protocol*.md`：orchestrator 與 subagent 的推理／驗證協定。
- `.claude/orchestration-policy.md`：由人類設定成本門檻與環境授權。
- `.claude/hooks/`：計畫、人類核准、憑證及危險命令硬性關卡。`settings.json` 只掛載
  `guard.py` 統一進入點，於單一直譯器行程內依序執行三道檢查（危險指令 → 憑證 →
  計畫閘門）加上第四道去識別化改寫（`redact_sensitive_info.py`），降低每次工具
  呼叫的啟動開銷；各檢查腳本仍可獨立執行驗證。另掛載 `block_pii_prompt.py` 於
  `UserPromptSubmit`，在使用者提交當下（送進模型前）先行阻擋疑似個資——因
  Claude Code 的 UserPromptSubmit 不支援改寫提示內容，只能整段阻擋並提示使用者
  自行遮蔽後重送，與 PreToolUse 的去識別化形成兩層縱深防禦。
- `CLAUDE.md`：載入上述規則的專案入口。

## 關卡順序

1. 唯讀工具與安全的唯讀 Bash 可用於蒐集資訊。
2. Claude 依核准模式建立 `.claude/plan/decomposition.md`；`strict`／`standard` 計畫
   必須列出 `## 允許修改範圍`，`light` 只要求基本拆解。
3. `standard`／`light` 在計畫通過關卡後即可施作；`strict` 必須等待人類審查，
   由人類在自己的終端執行 `python3 .claude/hooks/approve_plan.py`（Windows 環境無 `python3` 時改用 `python`）。
4. `strict` 核准紀錄只在 60 分鐘內有效，且 SHA-256 必須符合目前拆解文件；
   檔案工具在 `strict`／`standard` 下不得修改允許範圍外路徑。
5. 憑證與危險命令 hooks 獨立於計畫與人工核准關卡，三種模式都不豁免。

## 分級模式

人類可在 `.claude/orchestration-policy.md` 設定「核准模式」，依專案風險選擇：

| 模式 | 行為 | 適用情境 |
|---|---|---|
| `strict`（預設） | 拆解 ＋ 允許修改範圍 ＋ 綁定 SHA-256 的人類核准（60 分鐘 TTL） | 生產系統、個資、orchestration 調度 |
| `standard` | 拆解 ＋ 允許修改範圍，免人類核准 | 需要檔案邊界的一般開發 |
| `light` | 基本拆解，免人類核准 | 低風險且不需要授權控制的工作 |

三種模式下憑證與危險命令 hook 都獨立生效。核准模式只由人類設定，模型不得修改政策檔或
建議降級；欄位缺少或無法辨識時一律視為 `strict`。具體 hook 覆蓋邊界見「安全設計」。
`strict` 模式拒絕一般 Bash；只有唯讀命令與人類 policy allowlist 的測試／建置入口
可進入計畫／核准流程。Allowlist 入口仍可能執行專案程式，permissions 與 sandbox
才是真正邊界。

## 安裝

將本目錄的 `.claude/`、`CLAUDE.md` 與 `ORCHESTRATOR.md` 複製或合併到目標專案。
若目標已有同名檔案，必須手動合併，不要直接覆蓋。執行 hooks 需要 Python 3.9+。

```bash
cp -r integrated-harness/.claude your-project/
cp integrated-harness/CLAUDE.md your-project/     # 若已有，改為合併
chmod +x your-project/.claude/hooks/*.py
cp your-project/.claude/plan/decomposition.template.md \
   your-project/.claude/plan/decomposition.md
```

建議將本機狀態加入 `.gitignore`：

```text
.claude/.plan_approved
.claude/plan/decomposition.md
```

在 Claude Code 使用 `/hooks` 確認三支 PreToolUse hook 已載入。

## 安全設計

- 所有 deny 均使用結構化 `hookSpecificOutput.permissionDecision` 回覆。
- `plan_gate.py` 會比對目前支援檔案工具的核准紀錄與政策檔路徑並拒絕修改；
  Bash 命令直接出現 `.plan_approved`，或非唯讀 Bash 直接出現 `.claude` 時會攔截。
- 未知或新增工具不會自動受到同等保護；必須另行檢查 matcher、tool input／path schema、
  permissions 與 hook 支援。
- 唯讀 Bash 以 shell token 與 allowlist 判斷，不使用模糊的字串前綴。
- 修改已核准的拆解文件會使原核准失效。

安全 hooks 會攔截已知高風險命令與明顯硬編碼憑證，屬於縱深防禦。未命中不代表
操作已獲授權，也不能取代 Claude Code permissions、sandbox、Secret Manager、SAST、
CI secret scanner 與人工審查。

## 單位與技術堆疊

單位情境、技術堆疊與版本邊界集中設定於 `.claude/orchestration-policy.md`；
`ORCHESTRATOR.md` 只保留通用的專案與版本邊界。

## 需要你補充的設定

`.claude/orchestration-policy.md` 內標示 `<由人類設定>` 的欄位必須由人類填寫，
安裝後、正式啟用 `strict`／`standard` 模式前請逐一確認：

| 章節 | 欄位 | 用途 |
| --- | --- | --- |
| 核准模式 | 核准模式（`strict`／`standard`／`light`） | 決定是否需要人工核准與拆解嚴謹度 |
| 單位與技術堆疊 | 單位情境、後端、前端、資料庫、基礎設施與交付、安全與品質 | 讓 orchestrator 判斷風險等級與派工邊界；基礎設施與安全欄位刻意避免寫出具體廠商或產品名稱，僅需描述類型 |
| 單位與技術堆疊 | 允許的目標框架版本、升級規則 | 界定「屬於既有計畫」與「需另行核准」的框架異動範圍 |
| 模型對應 | 編排層／執行層／輕量層 | 換平台或換模型時只需改這裡，規則正文不動 |
| 成本門檻 | 單一任務最高模型成本、最長執行時間、可自主使用的付費外部資源 | 留空視為「一律詢問」；設定門檻可讓 orchestrator 在範圍內自主決定 |
| 環境授權 | 可自主操作的開發／測試環境、永遠必須詢問的正式環境 | 明確劃出施作自主權邊界，避免誤觸生產環境 |

未填寫的欄位一律視為「留空即詢問」的保守預設，不會自動放寬權限。

## 測試

```bash
bash tests/smoke_test.sh
bash tests/orchestration_test.sh
```
