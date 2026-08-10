# Sensitive Data Guard — GitHub Copilot (VS Code) 的敏感資料防線

阻擋明文憑證寫入，並阻擋提示詞與待寫入內容中的個資。這是 `sensitive-data-guard`
的 Copilot 移植版，與 Claude 版、Codex 版共用同一組偵測規則，但**產品行為刻意不同**
（見下方「與 Claude／Codex 的刻意差異」）。

> **狀態與範圍**：本套件依賴 VS Code 的 Agent hooks（Preview）。Windows 主線的
> PreToolUse 線路已於 Phase 0 spike 實機驗證（2026-07-24）；**`UserPromptSubmit` 的
> 阻擋輸出形狀尚未實機驗證**（見下方）。macOS / Linux 為**附帶支援、尚未於 Copilot
> 實機驗證**。僅於 Copilot **Agent mode** 生效。

> **與 `decomposition-gate` 互斥**：兩個 Copilot 模式**不得同時安裝**。兩者都註冊
> `PreToolUse` 且都包含 `hook_protocol.py`，同時複製進 `.github/hooks/` 會互相衝突。
> 安裝前請先移除另一個模式的檔案。

---

## 功能與用途

| 面向 | 說明 |
| --- | --- |
| 核心功能 | 明文憑證阻擋、待寫入內容個資阻擋、提示詞個資阻擋 |
| 管制範圍 | **所有工具**的 `tool_input`（遞迴掃描全部字串值），以及 `UserPromptSubmit` 的 `prompt` |
| 個資種類 | 身分證字號、手機、Email、地址、信用卡卡號、學號、護照號碼 |
| 主要用途 | 已有自己的流程與權限控制，只想加裝敏感資料檢查 |
| 不提供 | 危險命令紅線、拆解閘門、人類核准、編排 |

---

## 與 Claude／Codex 的刻意差異

這三項差異是設計決策，不是移植疏漏：

### 1. 個資採 deny，**不做遮罩改寫**

Claude／Codex 版偵測到個資時輸出 `permissionDecision="allow"` + `updatedInput`，
以遮罩後的內容續行。該機制在 VS Code 上**未經實機驗證**；若不被支援（或 Preview
契約日後漂移），輸出會退化成「allow 未遮罩的原始內容」——真實個資照原樣寫入，
且沒有任何錯誤訊息。這是「安全控制無聲失效」，正好落在 VS Code 的 fail-open 陷阱。

`deny` 沒有這種無聲失敗模式。代價是摩擦較高：Copilot 每次被擋都必須自行改用
去識別化資料，而不是由 hook 自動遮罩。

### 2. 個資與憑證都掃描終端機指令

Claude 版的遮罩刻意排除 Bash（改寫指令字串會破壞語法），但 deny 沒有這個問題。
且 Phase 0 spike **實測記錄** agent 在 `create_file` 被 deny 後會改走
`run_in_terminal` 並最終寫入成功——若個資防線不涵蓋終端機，
`echo "<身分證字號>" > out.txt` 可完全繞過。

### 3. 不依賴工具名白名單，遞迴掃描整個 `tool_input`

`multi_replace_string_in_file` 承載新內容的欄位名未經 spike 記錄。若以欄位名對應
擷取而猜錯，掃描會什麼都看不到而靜默放行——又一個無聲 fail-open。deny-only 的偵測
不需要知道哪個欄位是什麼，只需要知道待寫入的文字裡有沒有敏感資料；遞迴走訪同時
免疫 Preview 欄位改名。

**代價**：`filePath`、`explanation` 等欄位一併納入掃描，誤判面較大——例如 Copilot
的說明文字剛好引用了 Email，該次工具呼叫也會被擋。這是刻意取捨。

---

## 目錄結構

```
copilot/plugins/sensitive-data-guard/
├── README.md
├── hooks/                             # 這整個目錄複製到目標 repo 的 .github/hooks/
│   ├── sensitive-data-guard.json      # PreToolUse + UserPromptSubmit hook 設定
│   ├── launch.ps1                     # Windows 啟動器（參數化：腳本 + 事件名）
│   ├── launch.sh                      # POSIX/macOS/Linux 啟動器（未驗證）
│   ├── sensitive_data_guard.py        # PreToolUse 進入點（憑證 → 個資）
│   ├── block_pii_prompt.py            # UserPromptSubmit 進入點（個資）
│   ├── block_secrets.py               # 憑證偵測規則
│   ├── pii_patterns.py                # 個資偵測規則（由 shared/copilot/ 同步）
│   └── hook_protocol.py               # VS Code 線路邊界（由 shared/copilot/ 同步）
└── tests/
    └── smoke_test.sh                  # hook 行為驗證（24 情境 / 26 項斷言）
```

`launch.ps1` 與 `launch.sh` 為**參數化**版本（接收目標腳本與事件名稱），與
`decomposition-gate` 的硬寫版本刻意不同——本模式有兩個進入點，且錯誤路徑的
`hookEventName` 依事件而異。

---

## 安裝

1. 將 `hooks/` 內全部檔案複製到目標 repo 的 `.github/hooks/`（同層，
   `from hook_protocol import` 靠 Python 的 script-dir sys.path 解析）：

   ```bash
   mkdir -p your-project/.github/hooks
   cp hooks/* your-project/.github/hooks/
   ```

   > 若該目錄已有 `decomposition-gate` 的檔案，請先移除——兩模式互斥。

2. 在 VS Code 使用者設定啟用 Agent hooks 並納入本位置：

   ```jsonc
   {
     "chat.useCustomAgentHooks": true,
     "chat.hookFilesLocations": { ".github/hooks": true }
   }
   ```

3. **Reload Window**，並以 Copilot 的 `/hooks` 確認 `PreToolUse` 與
   `UserPromptSubmit` 兩個 hook 都已載入。

> **Python 直譯器**：Windows 啟動器會自動探測 `python.exe`（排除 WindowsApps Store
> 別名）。若探測不到，設定環境變數 `GUARDRAIL_PYTHON` 指向直譯器完整路徑。

---

## 運作原理

- **兩個事件**：`PreToolUse` 執行憑證檢查後執行個資檢查，任一命中即 deny；
  `UserPromptSubmit` 只檢查個資（與 Claude／Codex 的模式邊界一致，提示詞不擋憑證）。
- **編碼**：入站讀原始位元組並以 UTF-8 解碼；出站輸出 **ASCII-safe JSON** 以繞過
  Windows cp950 locale。
- **fail-open 鐵律**：VS Code 對「hook 執行出錯」或「輸出非 JSON」一律放行工具。
  故啟動器對任何例外都自印 deny，且輸出形狀必須與事件相符——對 `UserPromptSubmit`
  輸出 `PreToolUse` 形狀很可能被忽略而等同沒擋。
- **誤判降低**：憑證規則對明顯佔位符（`YOUR_API_KEY`、`<token>`、`${VAR}` 等）放行；
  信用卡候選值需通過 Luhn checksum；學號與護照號碼採標籤錨定。

### `UserPromptSubmit` 的必填欄位刻意最小化

`load_event` 對 `UserPromptSubmit` 只要求 `hook_event_name` 與 `prompt`。若比照
`PreToolUse` 要求 `cwd`／`session_id`／`transcript_path`，而 VS Code 實際未送其中任一
欄位，fail-closed 會變成封鎖使用者的**每一個**提示——包含他用來排除問題的那個提示，
形成無法自救的硬鎖死。

---

## 已知限制

- **`UserPromptSubmit` 阻擋輸出形狀未實機驗證**：spike 只證實輸入端可取得 `prompt`，
  未記錄「如何輸出才能真的擋下提示」。目前依已驗證的 `PreToolUse` 慣例類推，形狀集中
  於 `hook_protocol.block_prompt()` 一處。**在實機驗證前，這道防線不可宣稱有效。**
- **`send_to_terminal` 未納入**：是否承載可寫入內容未經驗證。
- **Preview 機制**：VS Code Agent hooks 仍在 Preview，契約可能漂移。
- **僅 Agent mode**：非 Agent 模式下不生效。
- **平台**：Windows 主線已驗；macOS / Linux 未於 Copilot 實機驗證（附帶支援）。
- **輸出污染即 fail-open**：任何讓輸出非合法 JSON 的情況都會使該次工具放行。
- **規則式偵測的固有極限**：regex 無法涵蓋混淆、編碼或間接寫入的所有變形；
  學號與護照在無鄰近標籤時可能漏判。本模式不能取代完整 DLP、SAST 或人工審查。
- **不掃描附件**：只掃描 `prompt` 純文字，不解析 PDF／Office 文件，不做圖片 OCR。

---

## 測試

```bash
bash tests/smoke_test.sh
```

涵蓋 24 情境／26 項斷言：線路邊界 3、憑證阻擋 4（含終端機與 `multi_replace`
的 `newString`）、個資阻擋 7（含終端機、`filePath`、Luhn 正負向）、涵蓋範圍與
輸出鐵律 4（未知工具、純 ASCII、事件名）、`UserPromptSubmit` 6（命中、事件名、
乾淨放行、憑證不擋、兩種錯誤路徑）。

根層另有三支回歸測試：

```bash
bash tests/copilot_sensitive_data_guard_test.sh   # 上述 smoke test 的 CI 入口
bash tests/copilot_shared_sync_test.sh            # 與 shared/copilot 無漂移
bash tests/pii_cross_platform_parity_test.sh      # 三平台 PII 行為完全一致
```

> 注意：smoke test 驗證的是 **Python hook 邏輯**（跨平台）。啟動器（`.ps1`/`.sh`）
> 屬平台接線，需由實機 E2E 檢查涵蓋。

---

## 授權與注意事項

- Hook 以你的權限執行任意程式碼。套用前請自行審閱程式碼內容。
- 請務必先於測試專案驗證，再套用到正式工作流。
- 本套件為送模／寫入前的規則式防線，不是完整 DLP 或惡意軟體掃描器。
