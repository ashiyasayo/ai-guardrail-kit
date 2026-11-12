# 暫緩啟用 GitHub immutable releases，待專案穩定後再評估

日期：2026-11-12

## 決策

- 目前不啟用 GitHub 的 immutable releases；`gh release view` 顯示 `immutable: false` 屬已知且接受的狀態。
- 待專案更加穩定後再啟用（使用者決定）。在此之前不需為此變更 repo 設定或 release workflow。

## 現況

- v0.15.0（以及先前各版）release 皆為 `immutable: false`，不是 workflow 的錯誤。
- 版本釘選目前靠 release 說明中的 `Immutable runtime identity`：Codex 安裝以
  `select-codex-mode --source github --ref <40-hex-commit>` 指定 commit SHA。保護在 SHA 層，不在 release 層。

## 該功能是什麼（既有知識，未查證官方文件）

- 啟用後，release 發布時 tag 不可移動、附件不可新增／修改／刪除，且刪除 release 後同名 tag 不可重用；
  並產生 release attestation 供下游驗證。
- 上述內容來自撰寫當時的既有知識，**未於本次對話對照官方文件核對**，啟用前須先查證。

## 取捨

- 啟用的好處：release 層級的供應鏈完整性，符合本專案以治理與安全為定位。
- 啟用的代價：發錯版無法修補或以同版號重發，只能發新的 PATCH 版，發版流程必須一次做對。
- 暫緩的風險：具 repo 寫入權限者理論上可刪除重建 tag 或替換附件；目前由 `main` 保護、CHANGELOG-only
  發版 PR、annotated tag 與 SHA 釘選降低影響。

## 重新評估的時機（【假設】建議值，使用者可修訂）

- 發版流程已穩定：連續數個版本沒有重發、撤回或手動修補 release。
- 完整回歸與 release workflow 長期維持綠燈，且沒有因 tag 或附件問題回頭修正。
- 使用者認定專案已足夠穩定。「穩定」的具體標準目前未定義。

## 啟用前待查

- 官方文件：啟用位置（repo 或 org 設定）、是否追溯既有 release、確切限制與例外。
- release workflow 是否需調整（例如附件須在發布前一次上傳完成、是否與先建 draft 再發布的流程相容）。
- 啟用後的回復手段：確認發錯版時的處理流程，並寫入 `VERSIONING.md` 或發版文件。
