# 2026-07-23 — Claude 側 PII 規則改以 `shared/claude/` 單一來源 + 同步腳本

一句話：把 Claude 側 PII 三件組從「手動複製 + parity 事後守護」升級為
「`shared/claude/` 唯一審核來源 + `sync-claude-hook-copies` 生成／`--check` 守護」，
結構上消除漂移，對稱既有的 Codex `shared/codex/` 機制（Layer 1）。

## 背景

Claude 側的 PII 三件組（`pii_patterns.py`、`block_pii_prompt.py`、
`redact_sensitive_info.py`）原本在 5 個位置各存一份實體副本：

- `claude/plugins/{sensitive-data-guard,harness,integrated-harness}/hooks/`（3 份）
- `harness/.claude/hooks/`、`integrated-harness/.claude/hooks/`（2 份 copy-in）

一致性僅靠 `tests/claude_hook_parity_test.sh` 的逐字節斷言「事後」守護，且該斷言只
比對「SDG plugin vs harness copy-in」，未涵蓋其餘位置。Codex 側早已改用
`shared/codex/` 單一來源 + `sync-codex-hook-copies`，Claude 側落後。

## 觸發此決策時發現的既有漂移

實作前的驗證（diff + `wc -l`）發現 **SDG plugin 的三個檔各多一個結尾空行**（107／80／121
行 vs 其餘 106／79／120 行），導致 `claude_hook_parity_test.sh` 當時即為紅燈——正是
手動複製機制已漂移卻未被擋下的實證。裁定以 4:1 多數的 106／79／120 行版本為 canonical，
修正 SDG 對齊。

## 決策

1. 新增 `shared/claude/` 存放 PII 三件組的唯一審核來源（內容 = canonical，位元組不變）。
2. 新增 `scripts/sync-claude-hook-copies`（忠實對稱 Codex 版：`cp -p` 生成、`cmp -s`
   `--check`、拒絕 symlink、失敗 exit 1），來源 `shared/claude/`、目標 5 個位置 × 3 檔。
3. 新增 `tests/claude_shared_sync_test.sh`（`run_all.sh` 以 glob 自動納入）。
4. 移除 `claude_hook_parity_test.sh` 中已被 `--check` 取代的逐字節斷言，避免雙軌漂移；
   保留 `block_secrets.py`／`block_dangerous_commands.py` 的行為語料（此二者為刻意分歧
   分支，不 byte 共用，不納入同步）。

## 範圍界線（本次不做）

- 跨平台合併（Claude ↔ Codex 共用同一份規則核心）＝ Layer 2。
- 合併 hook I/O 進入點（`guard.py`／`plan_gate.py`／`security_guard.py`）＝ Layer 3；
  平台 hook 協定不同，強行合併會把互斥選擇推到執行期、放大 fail-open 風險。

## 後果

- 正面：Claude 側自此結構性防止漂移；順手修好原本紅燈的 parity 測試；守護範圍由
  1 對擴大到全部 5 個位置。
- 代價：`shared/claude/` 的來源與 5 份副本必須維持位元組相同（marketplace sparse
  checkout 與 copy-in 皆讀 repo 內實體檔，故副本必須 commit）；修改規則須改來源後跑
  同步，而非直接編輯副本。
- 待辦：`scripts/sync-claude-hook-copies` 由編輯工具建立時未帶可執行位元，需
  `chmod +x` 後再提交，以對齊 `sync-codex-hook-copies` 的慣例（測試已用 `bash` 呼叫，
  不受影響）。

## 相關

- 對稱機制：`shared/codex/` + `scripts/sync-codex-hook-copies`。
- 附件送模前 PII 掃描提案：`.docs/vault/decisions/2026-07-23-local-attachment-pii-scanner-proposal.md`。
