# 個資召回強化與閘門加固設計

日期：2026-07-22
一句話摘要：擴充個資偵測規則（信用卡 Luhn／學號／護照）並升級 RULES 契約支援二次驗證，同時堵住 decomposition-gate 逃生口，並補齊相關文件與測試。

## 背景與目標

本次針對前一輪功能面分析所列的落差進行修正，範圍與方向已與使用者確認：

1. **個資召回**（架構層）：升級共用的 `pii_patterns.py` RULES 契約，加入信用卡 Luhn 驗證與連續 16 碼卡號、新增學號與護照規則。
2. **逃生口保護**：堵住 `decomposition-gate` 的 `.gate_disabled` 逃生口——禁止模型透過 Bash／寫入工具自建。
3. **light 模式**：僅補文件說明（維持行為）。
4. **regex 限制**：僅補文件說明（維持誠實揭露）。

## 修正 1：個資召回強化（RULES 契約升級）

### 契約變更

`pii_patterns.py` 的 `RULES` 由 3-tuple 升級為 4-tuple：

```
(名稱, 已編譯 regex, 遮罩函式, 驗證函式 | None)
```

規則命中的判定改為：**regex 命中 AND（驗證函式為 None 或 驗證函式(match) 回傳 True）**。

### 兩個 consumer 同步修改

- `redact_sensitive_info.py::redact`：`_sub` 閉包內先跑驗證函式，未過則原樣返回 `match.group(0)`（不遮罩、不計入命中）。
- `block_pii_prompt.py::find_pii_kinds`：由 `pattern.search` 改為 `pattern.finditer` 逐一比對，任一 match 通過驗證即計入該規則。

### 規則異動

| 規則 | 做法 | 驗證函式 |
| --- | --- | --- |
| 台灣身分證字號 | 不變 | None |
| 手機號碼 | 不變 | None |
| Email | 不變 | None |
| 地址 | 不變 | None |
| 信用卡卡號 | 放寬為 13–19 碼（含連續無分隔），用 Luhn 過濾誤判 | Luhn |
| 學號（新增） | 標籤錨定：`學號／學生證號／student id／student number` ＋ 英數編號 | None（靠標籤） |
| 護照號碼（新增） | 標籤錨定：`護照(號碼)／passport (no/number)` ＋ 8–9 碼數字 | None（靠標籤） |

### 學號／護照採「標籤錨定」的理由

台灣學號無全國統一格式且與身分證字號、任意編號高度重疊；ROC 護照為純 9 碼且無公開檢查碼。裸偵測會造成大量誤判，因此改為要求鄰近出現標籤關鍵字才觸發。這是精確率優先的取捨，犧牲無標籤裸資料的召回。

### 影響檔案（各 ×4 個位置，保持逐字元相同）

- `pii_patterns.py`
- `redact_sensitive_info.py`
- `block_pii_prompt.py`

位置：`harness/.claude/hooks/`、`claude/plugins/harness/hooks/`、`integrated-harness/.claude/hooks/`、`claude/plugins/integrated-harness/hooks/`。

## 修正 2：逃生口保護（decomposition-gate）

在 `decomposition_gate.py` 進入正常閘門判斷前，先做逃生口保護：**任何 Bash 指令或寫入工具目標涉及 `.gate_disabled` 一律 deny**，比照 `plan_gate.py` 對 `.plan_approved` 的既有做法。人類仍可在自己的終端機建立此檔。

影響檔案（Claude 專屬 2 份）：`decomposition-gate/.claude/hooks/decomposition_gate.py`、`claude/plugins/decomposition-gate/hooks/decomposition_gate.py`。

Codex 版 `decomposition_gate.py` 無 `.gate_disabled` 機制，實作時需再確認其無同類漏洞。

## 修正 3 & 4：純文件

- **light 模式**：在 `integrated-harness` README／MAINTENANCE 明確說明「選 light＝放棄檔案範圍管制，只保留『有拆解才能動』」。
- **regex 限制**：在文件再次強調「防線不是保證」，補上混淆／間接執行的已知盲點。

## 測試

- `tests/claude_redact_pii_test.sh`：新增連續 16 碼卡號（Luhn 過）遮罩、Luhn 不過的 16 碼不遮罩、學號、護照 fixture 與斷言。
- `tests/claude_block_pii_prompt_test.sh`：新增學號、護照 prompt fixture 與斷言。
- decomposition gate：新增「模型無法透過 Write／Bash 建立 `.gate_disabled`」測試。
- 既有 byte-identity／parity 測試因副本保持相同應續過。

## 文件與版號

- 更新：root `README.md`、`CHANGELOG.md`、`harness/README.md`＋`MAINTENANCE.md`、`integrated-harness/README.md`＋`MAINTENANCE.md`、`decomposition-gate/README.md`、`pii_patterns.py` docstring。
- 版號：harness `0.4.0→0.5.0`、integrated-harness `0.3.0→0.4.0`、decomposition-gate `0.1.2→0.2.0`（Claude）；Codex decomposition-gate 若無同類漏洞則不動。

## 已知限制

- 學號／護照的標籤錨定無法涵蓋無標籤的裸資料。
- Luhn 只驗證卡號格式合法性，無法確認卡號是否真實發卡。
- regex 防線無法涵蓋混淆與間接執行，屬本質限制。
