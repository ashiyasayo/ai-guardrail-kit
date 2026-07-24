# 支援 GitHub Copilot (VS Code) 護欄：可行性、決策與 Phase 1 實作

日期：2026-07-23（Phase 0 spike 與 Phase 1 實作於 2026-07-24 完成）

一句話摘要：VS Code Copilot 的 Agent hooks（Preview）足以承載本 kit 的硬阻擋護欄；
經實機 spike 驗證後，第一批以 decomposition-gate 移植，發行走 `.github/hooks/*.json`，
新增樹 `copilot/plugins/decomposition-gate/`，smoke 16/16 通過。

## 背景

使用者要求把本 kit（decomposition-gate / sensitive-data-guard / harness /
integrated-harness）延伸支援 GitHub Copilot (VS Code)。經三輪網路查證 + 實機
Phase 0 spike，確認 **enforcement 層可行**（先前依 2026-01 知識誤判為不可行，已推翻）。

## 三項定案決策（brainstorming 收斂）

1. **拆解產出物路徑（決策 1＝A）**：copilot-native `.github/guardrail/plan/decomposition.md`，
   逃生口 `.github/guardrail/plan/.gate_disabled`。與 Codex「各平台自帶路徑」一致，隔離乾淨。
2. **未知工具政策（決策 2＝A）**：只 gate 已知寫入向量，其餘與未知工具放行；缺口以
   README + 維護清單誠實標註。（貼近 Claude 版哲學；fail-closed 會誤擋大量合法工具，Copilot 不可用。）
3. **啟動器/平台（決策 3＝A + 阻擋性第 0 步）**：跨平台（Windows 主線已驗、POSIX/Mac
   附帶標未驗）；單一 Python 邏輯 + 各平台薄啟動器；powershell→python 橋列為先驗關卡。

## Phase 0 spike 實證結論（VS Code Insiders + Copilot，2026-07-24 實機）

| 項目 | 結論 | 意義 |
|------|------|------|
| powershell→完整路徑 python.exe 橋 | ✅ 通 | 入站讀原始位元組、UTF-8 解碼→中文完整；出站 ASCII-safe JSON→VS Code 正確解析、deny 生效 |
| 設定檔啟動器路徑 | ✅ 定案 | `${workspaceFolder}` 不可用（與 PowerShell `${var}` 語法衝突塌成空字串）；改用**工作區相對路徑**（hook cwd=工作區根） |
| S0.1 PreToolUse 含寫入內容 | ✅ 直接證實 | 自建 hook 抓到完整 `tool_input`（`create_file` 含 `filePath`+`content`）→ block_secrets 可寫入前掃描 |
| S0.2 UserPromptSubmit.prompt | ✅ 有 | block_pii_prompt 可行 |
| S0.3 `deny` 阻擋 | ✅ 有效但可繞過 | `create_file` deny 後，agent **現場錄得**改走 `run_in_terminal` 並連續嘗試 base64/unicode/暫存替換/bytes 等規避 → 護欄必須涵蓋終端機 |
| S0.4 SessionStart | ✅ 觸發 | inject_protocol 可行（後續批次） |
| S0.5 設定位置/格式 | ✅ 定案 | 只有 `.github/hooks/*.json`（扁平 + 平台鍵）會執行；`.claude/settings.json` 只被 `/hooks` 列出、不執行 |

**資安級行為**：VS Code 對「hook 執行出錯」或「輸出非 JSON」一律 `NonBlockingError` →
工具照放行（**fail-OPEN**）。故 gate 效力繫於「stdout 只有乾淨 ASCII-safe JSON」，
啟動器須 try/catch 一切錯誤並自印 deny。（佈線細節見 [[2026-07-23-vscode-copilot-hook-wiring]]）

**真實工具名**：`read_file`、`create_file`、`multi_replace_string_in_file`、
`run_in_terminal`、`send_to_terminal`、`get_terminal_output`。

## 修正後的各模式 feasibility

| 現有 hook | Copilot 可行性 |
|-----------|---------------|
| plan_gate / decomposition-gate | ✅ 已實作。涵蓋 `create_file` + `multi_replace_string_in_file`（依本質）+ `run_in_terminal`（**整體 gate**） |
| block_dangerous_commands | ✅ 掃 `run_in_terminal.command` |
| block_pii_prompt | ✅ UserPromptSubmit `deny` |
| block_secrets | ✅ PreToolUse 內容在 payload → 可寫入前擋 |
| redact_sensitive_info | 🟡 待驗 `updatedInput` 改寫 content（影響 sensitive-data-guard） |
| approve_plan | ✅ 外部腳本可沿用 |
| inject_protocol | ✅ SessionStart |

## run_in_terminal 處理方式（決策 2A 的修正，spike 實證背書）

原規劃「對 `run_in_terminal.command` 做寫入意圖正則（比照 Claude Bash）」。**spike 證明
對抗性 agent 會用 base64/bytes/暫存替換等手段繞過任何寫入意圖正則**，故改採 **Codex 式
「拆解前整體 gate」**（`codex` 版 `exec_command` 註解：`shell syntax is too broad to prove
write-free`）——拆解檔未完成時，`run_in_terminal` 一律 deny，不分辨讀/寫。
代價：拆解前連唯讀終端機也被擋，但符合「拆解前不做實質工作」的本意，且拆解檔一寫好即全放行。

## Phase 1 實作（已完成，2026-07-24）

新增樹 `copilot/plugins/decomposition-gate/`（來源佈局＝部署佈局，`hooks/` 整包 → `.github/hooks/`）：

```
hooks/  hook_protocol.py  decomposition_gate.py  launch.ps1  launch.sh  decomposition-gate.json
plan/   decomposition.template.md
tests/  smoke_test.sh
README.md
```

- **hook_protocol.py**：VS Code 線路邊界（欄位驗證、`deny`/`ask`，入站原始位元組解 UTF-8、
  出站 ASCII-safe JSON 寫 `stdout.buffer`）。
- **decomposition_gate.py**：三寫入向量 gate + 拆解檔標記檢查 + 拆解檔自我豁免 + 逃生口保護。
- **launch.ps1**：以 .NET Process 把原始 stdin 位元組交給完整路徑 python.exe；python 探測
  （`GUARDRAIL_PYTHON` → 排除 WindowsApps 的 `python.exe`）；錯誤自印 deny。
- **launch.sh**：POSIX/Mac（標未驗）。
- **設定**：扁平格式 + `windows`/`osx`/`linux` 鍵 + 工作區相對路徑。
- **測試**：`smoke_test.sh` 16 情境全通過（線路邊界、三向量、terminal 整體 gate、逃生口保護、
  逃生口生效、未知工具放行）；沿用 smoke 風格（Bash allowlist 可執行、與既有元件一致）。

## 發行/安裝模型
- copy-in：`hooks/*` → 目標 repo `.github/hooks/`；`plan/decomposition.template.md` →
  `.github/guardrail/plan/`；使用者設定 `chat.hookFilesLocations` 含 `.github/hooks`、
  `chat.useCustomAgentHooks:true`；Reload Window。
- README 誠實標註：Preview、僅 Agent mode、已知寫入向量清單與缺口、POSIX/Mac 未驗、
  輸出污染＝fail-open、多根工作區未驗、釘 spike 日期 2026-07-24。

## 風險與待驗項
- **Preview 契約漂移**：格式/欄位可能改版 → 以本文件實機證據為準、釘日期。
- **輸出污染＝fail-open**：以 ASCII-safe + stderr 分離 + 啟動器自印 deny 緩解。
- **POSIX/Mac 未實機驗**：附帶支援，標未驗。
- **待驗**：redact 的 `updatedInput` 改寫 content（下一批 sensitive-data-guard 時處理）。

## 後續批次（未做）
- inject_protocol（SessionStart）、soft instructions / chatmode。
- sensitive-data-guard（block_secrets 寫入前擋 + redact updatedInput 驗證）。
- 是否共用 Claude/Codex 的 write-intent 或 PII 單一來源（跨平台核心）。

## 關聯
- [[2026-07-23-vscode-copilot-hook-wiring]]（hook 佈線正解 gotcha）
- [[2026-07-23-claude-shared-pii-single-source]]（PII 單一來源，未來跨平台核心的基礎）
