# Copilot (VS Code) sensitive-data-guard：以 deny 取代遮罩，以遞迴掃描取代欄位對應

日期：2026-07-31

一句話摘要：Copilot 移植的第二個模式；因 VS Code Agent hooks（Preview）的 fail-open
特性，凡是「失效時會無聲放行」的機制都不採用——個資改為 deny 而非遮罩改寫，
內容擷取改為遞迴掃描而非欄位名對應。

## 背景

[[2026-07-23-copilot-vscode-support-plan]] 把 `sensitive-data-guard` 列為 Phase 1
（`decomposition-gate`）之後的既定後續批次，並標記一項待驗風險：
`redact_sensitive_info` 依賴的 `updatedInput` 改寫機制未經驗證。

## 決策

### 1. 個資採 deny，不做遮罩改寫

Claude／Codex 版輸出 `permissionDecision="allow"` + `updatedInput` 以遮罩後內容續行。
若 VS Code 不支援 `updatedInput`（或 Preview 契約日後漂移），該輸出會退化成
**allow 未遮罩的原始內容**——真實個資照原樣寫入，且無任何錯誤訊息。

這比「未驗證」更嚴重：它是**安全控制無聲失效**，且正好落在
[[2026-07-23-vscode-copilot-hook-wiring]] 反覆記載的 fail-open 陷阱。`deny` 沒有這種
失敗模式——擋住就是擋住，失效則明顯放行且可被測試偵測。

因此**不需要**先 spike 驗證 `updatedInput`：即使驗證通過，Preview 契約漂移仍會讓
遮罩路徑在未來某天無聲失效。deny 在任何契約狀態下的失敗模式都是可觀察的。

代價：與另兩平台的產品行為不同，摩擦較高。已在 README、ARCHITECTURE、CHANGELOG
標註為平台差異。

### 2. 個資與憑證都掃描 `run_in_terminal`

Claude 版的遮罩刻意排除 Bash，理由是「改寫指令字串容易破壞語法」——改採 deny 後
該理由已不存在。

而 Phase 0 spike **實測記錄**：`create_file` 被 deny 後，agent 立刻改走
`run_in_terminal` 並連續嘗試 base64／unicode 轉義／暫存替換／bytes 寫入，
**最終寫入成功**。若個資防線只涵蓋檔案寫入工具，用終端機重導向輸出到檔案即可
完全繞過。

代價：PII 範圍寬於 Claude／Codex，屬刻意分歧；終端機指令含 Email 等內容時可能誤擋。

### 3. 遞迴掃描整個 `tool_input`，不做欄位名對應

`multi_replace_string_in_file` 承載新內容的欄位名**未經 spike 記錄**（既有
`decomposition_gate.py` 只讀 `replacements[].filePath`）。若以欄位名對應擷取而猜錯，
掃描會什麼都看不到而靜默放行——又一個無聲 fail-open。

deny-only 的偵測不需要知道哪個欄位是什麼，只需知道「待寫入文字裡有沒有敏感資料」。
遞迴走訪同時免疫 Preview 欄位改名。副作用：不依賴工具名白名單，所有工具（含未知
工具）的 `tool_input` 都會被掃描——與 `decomposition-gate` 的「未知工具放行」
（決策 2A）刻意不同，因為資料外洩防線的正確方向是掃描範圍更廣。

代價：`filePath`、`explanation` 等欄位一併納入，誤判面較大。

### 4. `UserPromptSubmit` 輸出形狀依已驗格式類推，並隔離於單一位置

spike 只證實輸入端可取得 `prompt`，未記錄阻擋輸出的形狀。Claude 用
`decision`／`reason` 鍵，VS Code 的 PreToolUse 用
`hookSpecificOutput.permissionDecision`——形狀不同，VS Code 對前者的契約未知。

採【假設】同族 `hookSpecificOutput` 慣例，形狀集中於
`hook_protocol.block_prompt()`，日後驗證後改一行即可。文件明確標註該道防線在
實機驗證前不可宣稱有效。

**曾考慮但未採用**：同時輸出兩種形狀以提高命中機率。風險是若 VS Code 對未知鍵做
嚴格 schema 驗證，會判為無效輸出而 fail-open——反而更糟。

### 5. `UserPromptSubmit` 的必填欄位刻意最小化

只要求 `hook_event_name` 與 `prompt`。若比照 PreToolUse 要求 `cwd`／`session_id`／
`transcript_path`，而 VS Code 實際未送其中任一欄位，fail-closed 會變成封鎖使用者的
**每一個**提示——包含他用來排除問題的那個提示，形成無法自救的硬鎖死。個資掃描只
需要 `prompt` 本身，不需要檔案系統存取。

這是 fail-closed 原則的一個重要邊界：fail-closed 的代價必須是「可恢復的」。
PreToolUse 擋一次工具呼叫可恢復；UserPromptSubmit 擋掉所有提示則不可恢復。

### 6. 新增 `shared/copilot/`；啟動器刻意不共用

PII 規則以 `shared/copilot/` 為唯一來源（沿用每平台一份 shared 來源 ＋ 專屬 sync
腳本的既有模式），爆炸半徑只限 Copilot，不動 Claude／Codex。

已查證 `shared/claude/` 與 `shared/codex/` 的 `pii_patterns.py` **正則與遮罩輸出完全
相同**，差異僅註解與 typing 風格。新增第三份會擴大漂移面，故另建
`tests/pii_cross_platform_parity_test.sh`：同一語料餵三套 `RULES`，斷言命中種類與
遮罩輸出完全一致。

未採「新建 `shared/pii/` 跨三平台單一來源」：需改動 Claude 與 Codex 的 sync 腳本與
全部現有副本（含 5 份 Claude 副本），爆炸半徑過大，屬範圍外重構。**留作未來決策。**

`hook_protocol.py` 納入共用並同步到兩個模式（擴充為純附加，由 decomposition-gate
既有 16 案 smoke test 把關）。但**啟動器不共用**：Windows `launch.ps1` 是整個 Copilot
移植最難搞定、風險最高的產物，而兩模式互斥安裝、永不共存，跨模式分歧沒有執行期
交互風險，只有維護成本。新模式的啟動器改為參數化（兩個進入點、錯誤路徑的
`hookEventName` 依事件而異）。

## 實作與驗證

- 24 情境／26 項斷言 smoke test 全通過；三平台 PII parity 在 12 組語料上完全一致；
  `sync-copilot-hook-copies --check` 無漂移。
- Copilot 的 hook 測試首次納入根層 `tests/run_all.sh`（先前只有模式內 smoke test，
  CI 未涵蓋）。

## 施作中發現的兩個實務陷阱

1. **本儲存庫自身的護欄會攔截自己的原始碼。** 撰寫 `block_secrets.py` 時，註解裡用來
   說明連線字串規則的字面範例（`Pwd=` 形式後接明文值）命中了該規則本身而被 deny。
   Claude 版那份同樣的註解是在 hook 存在前就進版控的，所以從未被自己擋過。
   撰寫本筆記時再次踩到同一個坑——引用該範例來描述陷阱，又被擋一次。
   **教訓：描述規則時不要寫出會命中該規則的字面值。**

2. **`redact_sensitive_info` 會靜默改寫測試語料。** 含個資字面值的測試檔在寫入時會被
   自動遮罩，導致語料失效**而不易察覺**（不是攔截，是無聲改寫）。解法：測試語料一律
   以相鄰字串串接組出（例如身分證字號寫成兩段相鄰字串），檔案內不含連續字面值，
   執行期才組成完整樣本。此寫法已在兩支測試檔頭註明原因，避免後人「順手整理」
   成單一字串而破壞測試。

## 待驗項

- `UserPromptSubmit` 阻擋輸出形狀（需 VS Code 實機 spike）。
- `send_to_terminal` 是否承載可寫入內容。
- macOS／Linux 啟動器（`launch.sh`）——目前無 Mac 環境可驗。

## 關聯

- [[2026-07-23-copilot-vscode-support-plan]]
- [[2026-07-23-vscode-copilot-hook-wiring]]
- [[2026-07-23-sensitive-data-guard-mode]]
- [[2026-07-23-claude-shared-pii-single-source]]
