# Codex manager 外部指令失敗時帶出去敏後的 stderr

日期：2026-11-11

## 決策

`codex-runtime-manager.py` 呼叫外部 `codex` 失敗時（`_run_codex_plugin`、
`_remove_codex_marketplace`），`E_HOOK_FAILED` 的訊息帶出結束碼與去敏、截斷後的 stderr；
逾時帶秒數，啟動失敗帶例外類別與去敏訊息。格式：`<摘要> (exit <碼>: <stderr>)`。

## 理由

固定字串讓 Windows 上「測試其實執行了真的 codex」這個根因多花一輪診斷才找到
（見 `gotchas/2026-11-11-windows-which-prefers-real-codex-cmd.md`）。

## 邊界

- 訊息只走 CLI 的 stderr（人類終端機）。`dispatch` 的 hook 失敗輸出只帶錯誤代碼，
  不帶訊息；新增診斷不得流入 hook 輸出，那是模型可見的通道。
- 去敏是盡力而為的黑名單，不是保證：家目錄與使用者目錄、URL 內嵌帳密、
  `token`／`secret`／`password`／`api_key`／`authorization` 賦值、`Bearer` 值、常見前綴
  token。刻意不做「長字串一律遮蔽」，會連正常的長路徑與雜湊一起遮掉。
- 先去敏再截斷（300 字元），避免被截斷的半個 token 逃過比對；輸入先限制在 16 KiB。
- 只帶 stderr，不帶 stdout。
- 單一來源是 `scripts/codex-runtime-manager.py`，發佈副本 `hooks/manager.py` 須逐位元組
  一致（`tests/codex_loader_sync_test.sh`）；strict allowlist 無法執行同步腳本，需手動雙改。

## 已知限制

- `uninstall_guardrail` 在 marketplace 移除失敗時重新包裝成固定字串，尚未帶出 stderr。
- 去敏規則只以自行構造的樣本驗證，不能證明沒有漏網；新增可能含敏感資料的診斷來源時，
  須重新評估這個清單。
- 敏感測試樣本須以相鄰字串片段拼接，否則本 repo 自己的 guardrail 會擋寫入或遮罩資料。
