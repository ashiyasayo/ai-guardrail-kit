# VS Code Copilot Agent hooks 佈線：格式、位置、Windows、編碼與繞道

日期：2026-07-23（Phase 0 spike 於 2026-07-24 補全全部通關細節）

一句話摘要：讓 VS Code Copilot 的 hook 真的**執行且真的擋住**，要用對「位置 + 扁平格式 +
平台鍵 + 工作區相對路徑 + 原始位元組入站 + ASCII-safe 出站」，而且輸出稍有污染就 fail-open、
單一工具 `deny` 會被 `run_in_terminal` 對抗性繞過。

## 坑

在 Windows 版 VS Code (Insiders) + Copilot 設定 Agent hooks 時接連踩到：

1. **`.claude/settings.json` 只列不執行**：`/hooks` 會列出 `.claude/settings.json`（Claude
   相容格式）的 hook，但**實際不執行**（Preview 瑕疵，呼應 microsoft/vscode #296189）。
2. **格式不同**：Claude 是巢狀 `{ "matcher": "*", "hooks": [...] }`；VS Code 原生
   `.github/hooks/*.json` 是**扁平** `{ "type": "command", "windows": "...", "osx": "...", "linux": "..." }`。
3. **通用 `command` 以 bash 執行**：把 Windows 路徑塞進 `command` 會被 bash 當 POSIX 命令、
   反斜線被吃掉而靜默失敗；Windows 要用 `windows` 平台鍵（powershell）。
4. **`py`/`python` 找不到**：Store 執行別名在互動終端機可用，但 VS Code 生子程序時呼叫不到
   （`where py` 空白即徵兆）。須用完整路徑 `python.exe`，並排除 WindowsApps 別名。
5. **`${workspaceFolder}` 不可用**：VS Code **不展開** hook command 中的 `${workspaceFolder}`；
   更糟的是它與 **PowerShell 的 `${var}` 語法衝突**，被當成空變數 → 路徑塌成 `\.github\...` →
   `CommandNotFoundException`。**改用工作區相對路徑**（hook 的 cwd = 工作區根目錄，log 可見
   `cwd:"d:\\...ws"`），例如 `& '.\.github\hooks\launch.ps1'`。
6. **入站中文被轉成 `?`**：用 `$stdin | & $py` 這種 PowerShell 字串管線把 stdin 轉交 python，
   中文會被編碼成 `?`（編碼側損失，`$OutputEncoding=utf8` 在 PS 5.1 原生管線不可靠）。
7. **出站中文破壞 JSON → fail-open**：python 在 Windows 的 stdout 預設用 locale（cp950）編碼，
   中文變非法 UTF-8 位元組 → VS Code 判「non-JSON output」→ **忽略 deny → 工具照放行**。
8. **fail-OPEN 是預設**：VS Code 對「hook 執行出錯」或「輸出非 JSON」一律記 `NonBlockingError`
   並**放行工具**。不能靠「crash＝擋下」。
9. **`deny` 被對抗性繞過**：只擋 `create_file`，agent 立刻改走 `run_in_terminal`，並連續嘗試
   base64、unicode 轉義、暫存後替換、bytes 寫入、避開中文字面量……**最終寫入成功**。

## 解法

**位置 + 格式**：`.github/hooks/*.json`（工作區）扁平格式 + 平台鍵；工作區相對路徑：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "type": "command",
        "windows": "powershell -NoProfile -ExecutionPolicy Bypass -Command \"& '.\\.github\\hooks\\launch.ps1'\"",
        "osx": "sh './.github/hooks/launch.sh'",
        "linux": "sh './.github/hooks/launch.sh'"
      }
    ]
  }
}
```

**啟用**：使用者設定 `chat.hookFilesLocations` 含該位置、`chat.useCustomAgentHooks: true`；
改設定後 Reload Window。

**入站（原始位元組）**：Windows 啟動器讀 `[Console]::OpenStandardInput()` 的原始位元組，
用 .NET Process 的 `StandardInput.BaseStream.Write` 原樣寫進完整路徑 python.exe，**不經
PowerShell 字串編碼**。python 端 `sys.stdin.buffer.read().decode("utf-8")`。

**出站（ASCII-safe）**：python 用 `sys.stdout.buffer.write(json.dumps(obj).encode("ascii"))`
（`ensure_ascii=True` 把中文轉 `\uXXXX`），繞過 cp950；stderr 不得混入 stdout。

**錯誤一律自印 deny**：啟動器 try/catch 一切例外，任何失敗（含 python 找不到、非零結束）
都輸出一段合法 deny JSON，壓過 VS Code 的 fail-open 預設。

**deny 要涵蓋全寫入向量、且終端機整體 gate**：不能只擋 `create_file`，須同時擋
`multi_replace_string_in_file` 與 `run_in_terminal`；後者因對抗性繞道，**採整體 gate**
（拆解前一律 deny，不試圖用寫入意圖正則分辨讀/寫，比照 Codex `exec_command`）。

**deny 原因用詞**：明講「請先完成拆解」，不要寫得像「字元/內容檢查」——否則 agent 會誤判為
內容過濾而狂試規避，而非去補拆解檔。

## 驗證方式（spike 用）
- 用只把 stdin 寫進檔案的記錄器 hook，觀察 log 是否產生 → 區分「hook 有無執行」。
- 對照 VS Code Output 面板（GitHub Copilot Chat 頻道）的 `[PreToolUse] Running/Input/Output`；
  注意 Output 把 `tool_input` 截斷成 `"..."`、且會把輸出重新序列化，**不能**當內容/位元組來源，
  需靠自建 hook 抓完整 stdin、並實看檔案是否真的沒被建立來確認 deny 生效。

## 關聯
- [[2026-07-23-copilot-vscode-support-plan]]（可行性結論、三決策與 Phase 1 實作）
