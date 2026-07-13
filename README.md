# ai-guardrail-kit

本儲存庫提供 Claude Code 與 Codex 兩套平台實作。三種產品模式在各平台內皆應
**互斥、擇一啟用**；兩個平台的生命週期與核准語意不同，不應視為完全相同。
Claude Code 方案把 AI 協作開發從
單純的 prompt 約定，提升為「軟性決策規則 ＋ 硬性工具關卡（PreToolUse
hooks）」。三個目錄**功能與用途各自獨立、不可同時安裝**，其中
`integrated-harness` 是整合另外兩者能力的完整版，而非疊加安裝。

## 需求環境

- [Claude Code](https://docs.claude.com/en/docs/claude-code) CLI
- Python 3.8+（`decomposition-gate`／`harness`）／3.9+（`integrated-harness`）
- git（`integrated-harness` 的核准機制以 SHA-256 綁定拆解文件內容）

## 快速開始

Codex 使用 repository marketplace manifest、[`codex/`](codex/) 內的 plugin 與專案 hook
設定；完整的安裝、切換、更新、驗證及限制請見
[`docs/codex-marketplace.md`](docs/codex-marketplace.md)。Codex 三種模式皆需
Python 3.9+，不可沿用下列 Claude copy-in 安裝步驟。

從 GitHub 註冊 Codex marketplace：

```bash
codex plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --ref main --sparse .agents --sparse codex/plugins
```

`--sparse .agents --sparse codex/plugins` 下載 marketplace manifest 與 plugin 套件。註冊後請依照
[`docs/codex-marketplace.md`](docs/codex-marketplace.md) 使用 selector 選擇並啟用其中一種模式；也可先安裝
單一 plugin，例如：

```bash
codex plugin add decomposition-gate@ai-guardrail-kit
```

### Claude Code

Claude also provides a repository marketplace with mutually exclusive project
and local mode selection. See
[`docs/claude-marketplace.md`](docs/claude-marketplace.md) for registration,
selection, update, verification, removal, and scope behavior.

從 GitHub 註冊 Claude Code marketplace（目前專案）：

```bash
claude plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --scope project --sparse .claude-plugin plugins
```

如需僅供本機使用，將 `--scope project` 改為 `--scope local`。註冊後請依照
[`docs/claude-marketplace.md`](docs/claude-marketplace.md) 使用 selector 選擇並啟用其中一種模式。

三者皆為「複製即用（copy-in）」，沒有套件安裝或執行時相依，依需求擇一複製
對應目錄下的 `.claude/` 到你的專案（若專案已有 `.claude/settings.json`，
請手動合併 hooks 區塊，勿直接覆蓋）：

```bash
# 範例：只需要拆解品質閘門
cp -r decomposition-gate/.claude your-project/

# 範例：只需要人類核准與安全 hook
cp -r harness/.claude your-project/

# 範例：完整方案
cp -r integrated-harness/.claude your-project/

chmod +x your-project/.claude/hooks/*.py
```

詳細設定與核准流程請見各目錄的 `README.md`。

## 三個目錄總覽

| 目錄 | 一句話定位 | 拆解檢查 | 人類核准 | 安全 Hook | 完整編排層 |
| --- | --- | --- | --- | --- | --- |
| [`decomposition-gate/`](decomposition-gate/) | 任務拆解品質閘門（流程紀律） | 有 | 無 | 無 | 無 |
| [`harness/`](harness/) | 人類核准與安全 hook 防線（授權控制） | 無 | 有 | 有 | 僅有生成提示稿 |
| [`integrated-harness/`](integrated-harness/) | 前兩者的整合版 ＋ 完整編排層 | 有 | strict 模式有 | 有 | 有 |

## 各目錄說明

### decomposition-gate — 先想清楚、再動手

以 PreToolUse hook 封鎖寫入類工具，直到 Claude 完成任務拆解並寫入
`.claude/plan/decomposition.md`（須含「已知資訊」「缺少的資訊」與至少一個
`【假設】` 標記）。搭配「深廣思考協定」五階段（拆解 → 探索 → 深化 →
對抗式審查 → 輸出前驗證）。

- 屬「流程紀律」而非「授權控制」：拆解文件可由模型自行完成，不能視為
  人工審批或安全沙箱。
- 適用：個人開發、教學、PoC，或只想強制留下任務拆解的專案。

### harness — 人類核准與安全底線

一組可獨立複製到專案的 hooks：未取得人類核准（`touch .claude/.plan_approved`，
60 分鐘有效）時攔截一切寫入；另有兩道獨立防線——攔截疑似硬寫的憑證，以及
永久攔截毀滅性 Bash 指令（不因核准而豁免）。附一份用於產生 `ORCHESTRATOR.md`
的提示稿，但本目錄不含完整編排層。

- 屬「授權控制」：核准旗標只能由人類在自己的終端機操作，模型無法自我核准。
- 適用：已有計畫／編排規範、需要補上確定性施作授權與安全底線的專案。

### integrated-harness — 完整部署方案

整合 `decomposition-gate` 的拆解品質檢查與 `harness` 的人類核准及安全 hooks，再加上
完整的編排層（`ORCHESTRATOR.md`：任務分解、模型路由、任務委派、驗收、
授權邊界）與維護說明（`MAINTENANCE.md`）。核准以
`python3 .claude/hooks/approve_plan.py` 綁定拆解文件的 SHA-256，並提供
`strict`／`light` 兩種核准模式（由人類在政策檔設定，模型不得修改）。

- 適用：多人協作、高風險資料、正式系統，以及需要稽核軌跡的專案。
- 附自動化回歸測試（`tests/`），是三者中唯一有自動化測試的目錄。

## 如何選擇

1. 只想強制「先拆解、後實作」的思考紀律 → `decomposition-gate`
2. 已有自己的編排規範，只缺人工授權與安全底線 → `harness`
3. 需要完整方案（拆解品質 ＋ 人類授權 ＋ 安全底線 ＋ 編排規則）→
   `integrated-harness`

安裝方式見各目錄的 `README.md`；三者皆為複製即用（copy-in），彼此沒有
執行時相依。

## 維護注意事項

- 三個目錄的閘門 hook **不得互相覆蓋**：`decomposition-gate` 的
  `decomposition_gate.py` 檢查「拆解是否完成」；`harness` 的 `plan_gate.py`
  檢查「人類是否核准」；`integrated-harness` 的 `plan_gate.py` 兩者皆查。
- `harness` 與 `integrated-harness` 的 `block_secrets.py`、
  `block_dangerous_commands.py` 為同源分支：修補任一邊的繞過手法時，
  須檢查另一邊是否需同步移植（詳見
  [`integrated-harness/MAINTENANCE.md`](integrated-harness/MAINTENANCE.md)）。
- `harness` 與 `integrated-harness` 的 `settings.json` 只掛載 `guard.py` 統一進入點，
  由它在單一直譯器行程內依序執行三道檢查；hook 檔案須整組複製，
  修改任一檢查腳本後應執行 `tests/claude_guard_test.sh` 回歸。
- Regex hooks 是防線不是保證，無法涵蓋混淆、間接執行等所有變形；須搭配
  Claude Code 權限設定、SAST、Secret Manager 與人工審查。
