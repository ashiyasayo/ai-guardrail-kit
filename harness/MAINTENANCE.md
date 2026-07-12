# Harness 維護說明

本文件只保留設計理由與跨產品維護原則。安裝、核准流程、測試與已知限制以
`README.md` 為準；本文件不重複其內容。

## 設計理由

- `harness/` 是**獨立、輕量**的安全防線，定位是掛到「已經有自己編排規則」的專案上，
  補一道人工核准與紅線攔截。它刻意不解析拆解文件、不綁定計畫內容，也沒有政策引擎。
- 三支 hook 以「單一 regex 規則＋exit code 訊號」實作，優先**簡單與可稽核**：
  每條規則獨立、看得懂、易於逐條驗證。這是相對 `integrated-harness` 的自覺取捨。
- `settings.json` 只掛載 `guard.py` 一條 PreToolUse 規則：三支檢查腳本改以
  `check(data)` 函式供 `guard.py` 匯入，於單一直譯器行程內依序執行
  （危險指令 → 憑證 → 計畫閘門），將每次工具呼叫的啟動成本從三次降為一次。
  各腳本仍保留獨立的 `main()`，可單獨執行驗證；複製部署時四個檔案缺一不可。

## 與 integrated-harness 的關係（重要）

`harness/` 與 `integrated-harness/` 是**能力不同的兩個產品**，不是同一套程式的兩份拷貝，
也**不要求 hook 逐行同步**。因為部署採「複製其中一個目錄的 `.claude/`」的互斥安裝模式，
每個目錄必須自我完整，實體共用不可能。

三支同名 hook 的差異是刻意的：

| Hook | harness（本目錄） | integrated-harness |
|---|---|---|
| `plan_gate.py` | 人工核准旗標（`touch .plan_approved`，60 分鐘 TTL） | 政策驅動 strict／standard／light，綁定拆解文件 SHA-256 與允許範圍 |
| `block_dangerous_commands.py` | 單一 regex 比對 | `shlex` 逐 token／分段解析，抗變形更強 |
| `block_secrets.py` | regex 比對，exit code 訊號 | 結構化 schema 檢查與 JSON 決策輸出 |

**取捨的代價**：本目錄的安全 hook 以 regex 為主，對罕見或刻意混淆的變形（分開/長短
旗標、別名、間接執行）防禦力弱於 integrated 的 tokenized 版本。若你需要更強的
確定性攔截，請改用 `integrated-harness`。

**跨產品同步原則**：`block_secrets.py` 與 `block_dangerous_commands.py` 兩支的**意圖**
與 integrated 版重疊。修補其中一個共同失敗模式後，**必須評估另一產品是否也受影響**；
只有在行為契約相同時才移植，且兩邊各自以自己的測試驗證。共用意圖的規則若只補一邊，
會使兩個產品的防護強度悄悄分歧（此類漏洞確實發生過）。

## 已知限制

- 安全 hook 是縱深防禦，非保證：regex 無法窮舉所有危險變形或編碼後的憑證，
  仍須搭配 Secret Manager、SAST、CI secret scanner 與人工審查。
- 核准旗標為時間窗（非綁定單一計畫）：60 分鐘內的所有寫入都在核准範圍內。
  需要逐計畫核准時，請縮短 `APPROVAL_TTL_SECONDS` 或改用 `integrated-harness` 的
  SHA-256 綁定核准。
- 其餘操作性限制與白名單擴充方式見 `README.md` 的「已知限制」與「維護」段落。
