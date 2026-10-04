# Codex hook 與沙箱相容性修正

## 影響矩陣

| 平台 | 模式 | 發佈型態 | 本次範圍 |
| --- | --- | --- | --- |
| Codex | 四模式 | marketplace、離線 runtime archive、checkout | 共用事件正規化、PII 回寫、接線與契約測試 |
| Codex | harness、integrated-harness | 同上 | 取代不受支援的 ask 核准契約 |
| Codex | decomposition-gate、integrated-harness | 同上 | 計畫草稿移至 `.guardrail/plan/decomposition.md` |
| Codex | loader、所有模式 | project/local/user selector、global install | matcher、診斷與 bootstrap 副本同步 |
| Claude | 四模式 | shared、marketplace、copy-in、global install | 不適用：Claude 的事件、ask 與 `.claude` 計畫契約未改變 |
| Copilot | decomposition-gate、sensitive-data-guard | copy-in | 不適用：VS Code hook 協定及 `.github` 計畫位置未改變 |
| 發佈索引 | 全部 | `.agents/`、`.claude-plugin/` | 入口未新增或移除，不需改索引；Claude 行為未改，不升 plugin 版號 |

## 契約

以 [官方 Hooks 文件](https://learn.chatgpt.com/docs/hooks) 的 `Bash`／
`tool_input.command` 為標準；`apply_patch` 同樣使用 `command`。
共用協定接受舊 `exec_command`／`cmd`／`patch` 輸入，但拒絕互相矛盾的別名。
PII 回寫使用官方 `updatedInput.command`，不回傳舊 patch 欄位。

## 沙箱與遷移

計畫草稿放在工作區 `.guardrail/plan/decomposition.md`，不再要求模型寫入受保護的
`.codex/`。既有計畫請由人類檢查後搬移；不自動複製或回退舊計畫，避免採用過期範圍。
政策、selector 與 decomposition 緊急停用檔仍留在 `.codex/guardrail/`；搬移草稿
不代表授權模型修改政策或建立停用旗標。integrated-harness 可接受只修改計畫的 patch，
混入實作、政策或 Move 目標時不適用草稿豁免。

安裝／更新 loader、下載 runtime 與 selector 登錄是管理操作，應由人類終端機執行，
或經平台授權。hook 熱路徑離線，不要求關閉 sandbox。更新 loader 後，必須重新在
目標 Codex 用戶端的 `/hooks` 審閱當前 hook 定義，並開啟新 thread。

## 診斷與驗收

`verify-codex-mode <mode> --scope <scope> --diagnose [project-dir]` 檢查指定與
有效 selector、registry、cache、loader 與 matcher。一般 verify 只驗證 selector/cache。
兩者都不冒充宿主的 hook 信任、feature 設定、沙箱權限或實際執行證據。

同步測試、官方事件 fixture 測試與離線 loader 程序測試屬確定性回歸。
真實 Codex 整合測試須另外明確啟用；略過時不得宣稱已驗證 CLI／App 執行。

## 人類終端機一次性核准

目前 Codex 不支援 PreToolUse ask。以下指令只能由人類在自己的終端機執行，模型不得
代跑、改核准紀錄或要求核准庫的寫入權限。

```bash
guardrail_bin="${CODEX_HOME:-$HOME/.codex}/guardrail/bin"
python3 "$guardrail_bin/codex-runtime-manager.py" approve --project /path/to/project --command 'npm test'
# 審閱完整 JSON（專案、cwd、模式、內容與雜湊）後，以 preview 顯示的值確認
python3 "$guardrail_bin/codex-runtime-manager.py" approve --project /path/to/project --command 'npm test' --confirm <SHA256>
```

patch 改用 `--patch-file reviewed.diff`。若 hook 的 input 含額外欄位、或 session cwd
是子目錄，使用 `--event-file reviewed-event.json`，包含完整 `tool_name`、`tool_input`
及 `cwd`，確保核准內容與實際事件一致。三種輸入擇一；preview 不會授權。

憑證存放在 `$CODEX_HOME/guardrail/approvals/`，不得位於專案內，也不得把該目錄
加入模型的 writable roots。憑證 10 分鐘內限一次匹配操作，綁定專案、cwd、模式、
可執行工具輸入（不含 description 說明欄位）、計畫與政策雜湊。修改草稿後需要重新核准；永久安全拒絕仍然有效。
憑證消耗可能早於其他安全 slot 的拒絕，因此被其他 guard 阻擋後需重新審閱。

hook 必須能在受保護核准庫內取得消耗鎖並刪除憑證。若執行環境將 hook 也限制成
無法寫入該目錄，會明確 deny；由人類自行執行操作，不應把核准庫開放給模型。
此方案依賴平台的檔案寫入隔離，不是外部簽章授權，也不適用模型具有完整主機寫入權限
的威脅模型。light 的計畫仍須由人類建立／修改，不能透過可寫草稿擴大免核准範圍。

## 真實宿主測試

```bash
# 需要已安裝 Codex CLI，並允許本機 loopback listener；不使用模型額度
AGK_CODEX_HOST_TEST=1 bash tests/codex_host_integration_test.sh
```

測試使用隔離 CODEX_HOME、暫存專案與本機 Responses fixture，不使用帳號或複製憑證；只對自行產生的測試 hook 使用
一次性 trust bypass，保留 workspace-write 沙箱。驗證真正事件觸發、deny 阻擋與
PII updatedInput 回寫；預設不啟動 CLI 或 listener。此測試不驗證 App、Windows 或真實
使用者的持久信任狀態，也不代表一次性核准庫在所有宿主皆可寫。

## 發佈邊界

本次 archive 與 manifest hash 為工作樹產物，尚未發佈。正式遠端發佈前，先提交
archive，再將 manifest 的 release commit 與 archive URL 釘到該不可變 archive commit，
依既有來源驗證規則完成遠端取回測試；不能用舊 commit URL 搭配新 hash 宣稱已可遠端
安裝。本次本機回歸使用明確開啟的 development source，不修改使用者已安裝的釘版。

## 本次驗證紀錄（2026-10-04）

- `scripts/sync-codex-hook-copies --check`、`scripts/sync-codex-loader-copies --check` 通過。
- `AGK_TEST_PROFILE=full bash tests/run_all.sh` 通過；一般回歸中的宿主測試採 opt-in。
- 最後調整後另跑 approval、guardrail、loader contract、marketplace archive 一致性測試，均通過。
- macOS／Codex CLI 0.160.0 的 `bash tests/codex_host_integration_test.sh --run` 另行通過：
  使用本機 fixture、隔離設定與 workspace-write，驗證 Bash deny、patch PII 回寫、
  未核准拒絕、核准後執行及重放拒絕。測試停用 plugin／apps 自動載入並排除暫存目錄
  的一般沙箱寫入權限；模型不取得核准庫的寫入權限。
- 尚未驗證 Windows、Linux、Codex App、使用者持久信任狀態與正式遠端下載。
  現有安裝未變動；正式發佈仍須處理上節的 commit／URL 釘版。
