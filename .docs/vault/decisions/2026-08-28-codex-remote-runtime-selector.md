# Codex 遠端 selector 與全域 loader 解耦

日期：2026-08-28

## 決策

Codex 只安裝一個使用者層級的 `ai-guardrail-loader` plugin。四種模式不再以
`codex plugin add/remove` 作為全域互斥狀態，而由每個專案的 runtime selector
（`project`、`local`、`user`）釘住 mode、ref、commit、archive SHA-256 與完整
entrypoints。loader 從 selector 解析 content-addressed runtime cache，hook 熱路徑
只執行已驗證內容，不連網也不依賴 checkout。

## 理由

Codex plugin 安裝是使用者層級；把 mode plugin 當成切換單位會讓專案 A 的切換移除
專案 B 所需的全域 plugin。穩定 loader 將 Codex hook 接線固定在 `$CODEX_HOME`，
selector 只管理專案 runtime，因此不同專案可同時使用不同 mode 與不同釘版。

## 影響

- `runtime-manifest.json` 固化 release ref、commit、archive size／SHA-256；本 repo
  的示範 manifest 以核准 GitHub raw HTTPS archive 提供來源。
- cache 使用 `$CODEX_HOME/guardrail/runtime-cache/sha256/<digest>/`，selector commit
  同步寫入 `selector-index.json`，供安全的低頻 prune 與 loader 引用檢查使用。
- 舊 TOML／hooks marker 僅在完整且可辨識時遷移；混合或殘缺集合拒絕並維持原 bytes。
- Claude、Copilot、copy-in 及既有 shared hook 行為不屬本決策範圍。
