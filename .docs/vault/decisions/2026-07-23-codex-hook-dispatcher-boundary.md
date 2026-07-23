# Codex hook dispatcher 合併邊界

日期：2026-07-23

## 決策

Codex 僅將危險命令與秘密寫入兩道「純 deny」檢查合併到
`security_guard.py`。計畫閘門與 PII hook 維持獨立程序。

## 理由

- 危險命令與秘密檢查只有「不輸出／deny」兩種結果，合併後可維持既有優先順序。
- 計畫閘門可能回傳 Codex 原生 `ask`。
- PII hook 可能回傳 `allow` 與 `updatedInput`。
- 在未確認 Codex 對單一 hook 同時包含 ask 與 updatedInput 的契約前，不合併後兩者，
  避免為了減少一次 Python 啟動而改變授權或去識別化語意。

## 結果

`exec_command` 的純安全檢查由兩次 Python 啟動降為一次；發佈副本由
`shared/codex` 與 `scripts/sync-codex-hook-copies` 管理。
