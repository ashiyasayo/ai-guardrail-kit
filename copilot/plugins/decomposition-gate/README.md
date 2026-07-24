# Decomposition Gate — 深廣思考協定的 GitHub Copilot (VS Code) 硬性關卡

將「深廣思考協定」從軟性提示升級為 GitHub Copilot（VS Code Agent hooks）的硬性流程關卡。
在 Copilot 完成任務拆解（decomposition）之前，透過 PreToolUse hook 封鎖寫入類工具，
強制它「先想清楚、再動手」。這是 `decomposition-gate` 的 Copilot 移植版，
與 Claude 版、Codex 版共用同一套思考協定，僅平台接線不同。

> **狀態與範圍**：本套件依賴 VS Code 的 Agent hooks（Preview）。Windows 主線已於
> VS Code Insiders + Copilot 實機驗證（2026-07-24）；macOS / Linux 為**附帶支援、
> 尚未於 Copilot 實機驗證**。僅於 Copilot **Agent mode** 生效。

---

## 功能與用途

| 面向 | 說明 |
| --- | --- |
| 核心功能 | 檢查 `.github/guardrail/plan/decomposition.md` 是否存在並含必要標記 |
| 管制範圍 | `create_file`、`multi_replace_string_in_file`、`run_in_terminal`（整體 gate） |
| 放行條件 | 拆解檔通過最低格式檢查；唯讀工具、未知工具、拆解檔本身的建立不受阻擋 |
| 主要用途 | 將「先分析、後實作」從提示文字提升為可執行的 Copilot PreToolUse 關卡 |
| 不提供 | 人類核准、核准期限、憑證掃描、危險命令紅線、模型路由 |

它屬於「流程紀律」而非「授權控制」：拆解檔可由模型自行完成，通過後便能繼續。

---

## 管制的寫入向量（已知清單）與缺口

本 hook 明確管制以下**已知寫入向量**；拆解檔未完成前一律 deny：

| 工具 | 管制方式 |
| --- | --- |
| `create_file` | 依工具本質封鎖（撰寫拆解檔本身除外） |
| `multi_replace_string_in_file` | 依工具本質封鎖 |
| `run_in_terminal` | **整體 gate**——不試圖分辨讀/寫。shell 語法無法證明無寫入，
  且實測對抗性 agent 會用終端機（base64、bytes、暫存後替換等）繞過任何「寫入意圖」正則 |

其餘工具（`read_file`、`get_terminal_output` 等唯讀工具）與**任何未知工具**一律放行，
讓 Copilot 在拆解完成後正常運作。

**已知缺口（誠實標註）**：VS Code / Copilot 未來若新增其他寫入工具，在其被加入上表前
會繞過本 gate。本清單需隨平台演進維護。若從 hook 觀察到新的寫入工具，逐一補入即可。

---

## 目錄結構

```
copilot/plugins/decomposition-gate/
├── README.md
├── hooks/                             # 這整個目錄複製到目標 repo 的 .github/hooks/
│   ├── decomposition-gate.json        # PreToolUse hook 設定（扁平格式 + 分平台鍵）
│   ├── launch.ps1                     # Windows 啟動器（已驗證）
│   ├── launch.sh                      # POSIX/macOS/Linux 啟動器（未驗證）
│   ├── decomposition_gate.py          # PreToolUse hook 主程式（模式邏輯）
│   └── hook_protocol.py               # VS Code 線路邊界（欄位驗證 + deny 輸出）
├── plan/
│   └── decomposition.template.md      # 拆解產出物範本
└── tests/
    └── smoke_test.sh                  # hook 行為驗證（16 情境）
```

---

## 安裝

1. 將 `hooks/` 內全部檔案複製到目標 repo 的 `.github/hooks/`（四支同層，
   `from hook_protocol import` 靠 Python 的 script-dir sys.path 解析）：

   ```bash
   mkdir -p your-project/.github/hooks
   cp hooks/* your-project/.github/hooks/
   ```

2. 將拆解範本複製到 guardrail 目錄：

   ```bash
   mkdir -p your-project/.github/guardrail/plan
   cp plan/decomposition.template.md your-project/.github/guardrail/plan/
   ```

3. 在 VS Code 使用者設定啟用 Agent hooks 並納入本位置：

   ```jsonc
   {
     "chat.useCustomAgentHooks": true,
     "chat.hookFilesLocations": { ".github/hooks": true }
   }
   ```

4. **Reload Window**，並以 Copilot 的 `/hooks` 確認 PreToolUse hook 已載入。

> **Python 直譯器**：Windows 啟動器會自動探測 `python.exe`（排除 WindowsApps Store 別名）。
> 若探測不到，設定環境變數 `GUARDRAIL_PYTHON` 指向直譯器完整路徑。

---

## 使用流程

1. 開始新任務。Copilot 若嘗試寫入（建檔 / 編輯 / 執行終端機），會被 deny，
   並收到「請先完成拆解，寫入 `.github/guardrail/plan/decomposition.md`」的提示。
2. Copilot（或你）複製範本填寫拆解內容，須含：`## 已知資訊`、`## 缺少的資訊`、
   至少一個 `【假設】`。
3. 拆解完整後，寫入向量即自動放行，Copilot 進入實作。

### 緊急停用關卡

建立逃生口檔案即可暫時放行所有寫入。**此檔只能由你在終端機建立**——模型透過工具
自建一律被 deny：

```bash
touch .github/guardrail/plan/.gate_disabled   # 完成緊急修復後移除
rm .github/guardrail/plan/.gate_disabled
```

---

## 設定項（可調整）

以下常數位於 `hooks/decomposition_gate.py` 檔頭：

| 常數 | 預設值 | 說明 |
| --- | --- | --- |
| `PLAN` | `.github/guardrail/plan/decomposition.md` | 拆解產出物路徑 |
| `GATE_BYPASS` | `.github/guardrail/plan/.gate_disabled` | 逃生口檔案 |
| `MARKERS` | `## 已知資訊` / `## 缺少的資訊` / `【假設】` | 拆解檔必要標記 |
| `FILE_WRITE_TOOLS` | `create_file` / `multi_replace_string_in_file` | 受管制的檔案寫入工具 |
| `TERMINAL_TOOL` | `run_in_terminal` | 整體 gate 的終端機工具 |

---

## 運作原理（技術依據，均有 Phase 0 spike 實證）

- **設定位置/格式**：只有 `.github/hooks/*.json`（扁平格式 + `windows`/`osx`/`linux`
  平台鍵）會執行；`.claude/settings.json`（巢狀 Claude 格式）只被 `/hooks` 列出、不執行。
- **啟動器路徑**：使用**工作區相對路徑**（hook 的 cwd = 工作區根目錄）。
  不可用 `${workspaceFolder}`——VS Code 未展開，且與 PowerShell 的 `${var}` 語法衝突。
- **編碼**：入站讀原始位元組並以 UTF-8 解碼；出站輸出 **ASCII-safe JSON**
  （`ensure_ascii=True`）以繞過 Windows cp950 locale。
- **決策格式**：`hookSpecificOutput.permissionDecision`（`deny` / `allow` / `ask`）
  搭配 `permissionDecisionReason`；hook 一律 exit 0 搭配 JSON 輸出。
- **fail-open 鐵律**：VS Code 對「hook 執行出錯」或「輸出非 JSON」一律視為
  `NonBlockingError` → 工具照放行。故 gate 效力繫於「stdout 只有乾淨 ASCII-safe JSON、
  stderr 不混入」，且啟動器對任何例外都自印 deny。

> Hooks API 為 Preview，事件與欄位可能隨版本變動（本文件以 2026-07-24 實機證據為準）。
> 部署前請以官方 hooks reference 為準，並用 `/hooks` 確認實際載入狀態。

---

## 已知限制

- **Preview 機制**：VS Code Agent hooks 仍在 Preview，契約可能漂移。
- **僅 Agent mode**：非 Agent 模式下不生效。
- **平台**：Windows 已驗；macOS / Linux 未於 Copilot 實機驗證（附帶支援）。
- **多根工作區**：cwd 假設為單資料夾工作區根目錄，多根工作區行為未驗。
- **輸出污染即 fail-open**：任何讓輸出非合法 JSON 的情況都會使該次工具放行。

---

## 測試

```bash
bash tests/smoke_test.sh
```

涵蓋 16 情境：線路邊界 3（非法 JSON / 缺欄位 / 錯誤事件名皆 deny）、檔案寫入向量 6、
run_in_terminal 整體 gate 2、逃生口保護 3（三向量自建皆 deny）、逃生口生效 1、
未知工具放行 1。全部通過才回傳 exit 0。

> 注意：smoke test 驗證的是 **Python hook 邏輯**（跨平台）。啟動器（`.ps1`/`.sh`）
> 屬平台接線，由 Phase 0 實機 spike 與手動 E2E 檢查涵蓋。

---

## 授權與注意事項

- Hook 以你的權限執行任意程式碼。套用前請自行審閱程式碼內容。
- 請務必先於測試專案驗證，再套用到正式工作流。
- 本套件為流程輔助，不能取代模型本身的能力上限。
