# 2026-07-22 Codex 有各自獨立的平行 PII 實作，改 Claude 端不會同步到 Codex

一句話：個資規則不是單一事實來源——Claude 與 Codex 各有一份，改一邊不影響另一邊。

## 坑

擴充 Claude 端個資規則（`pii_patterns.py`）時，容易誤以為全 repo 共用一份。實際上：

- **Claude 端**：`pii_patterns.py` 存在於 4 個位置（harness／integrated-harness 的
  copy-in 與 packaged），彼此逐字元相同；consumer 是 `redact_sensitive_info.py`
  （PreToolUse 去識別化）與 `block_pii_prompt.py`（UserPromptSubmit 阻擋）。
- **Codex 端**：另有一份 `shared/codex/pii_patterns.py`（源頭，會產生／散佈到
  `codex/plugins/harness/hooks/` 與 `codex/plugins/integrated-harness/hooks/`），
  consumer 是 `shared/codex/pii_guard.py`（同時處理 prompt 阻擋與 patch 去識別化）。
  契約風格不同（typed、`from __future__ import annotations`），與 Claude 端**非**
  逐字元相同，無法直接互相複製。

## 現況更新

2026-07-22 Claude 端先將 `RULES` 由三元組升級為四元組（+驗證函式），並新增
信用卡 Luhn（13–19 碼）、學號、護照（標籤錨定）規則。Codex 端當時暫緩同步。

2026-07-23 Codex 已完成移植：`shared/codex/pii_patterns.py` 與 `pii_guard.py`
採相同四元組契約與規則能力，並透過 `scripts/sync-codex-hook-copies` 散佈到兩個
Codex plugin；兩個 Codex plugin 版號皆為 0.5.0。兩平台仍保留各自的 I/O 與
hook 協定實作，之後修改規則仍須同步評估，不能直接假設會跨平台自動更新。

## 相關

- 設計：[[../decisions/2026-07-22-pii-recall-and-gate-hardening-design]]
