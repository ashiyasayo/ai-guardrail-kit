# 回歸測試 profile 分層

日期：2026-08-12

## 決策

`tests/run_all.sh` 預設執行快速 `smoke` profile；Claude 與 Codex 的完整模式切換測試
保留於 `full` profile。完整 profile 由 `AGK_TEST_PROFILE=full` 手動執行，或由 CI 的
每週排程與手動 workflow 執行。

## 理由

Codex 模式切換測試在 Windows／Git Bash 上歷史約需 14–19 分鐘，近期優化後同一台主機
實測約 16 分鐘；Claude 模式切換測試也約需 2 分鐘。它們是完整交易與跨模式情境驗證，
不是日常快速健康檢查。將測試執行策略分層可保留覆蓋範圍，同時避免每次提交都等待
完整模式矩陣。

## 邊界

這只改變回歸測試的預設執行 profile，不移除任何模式、selector、global install 或
發佈副本。CI 的 push／pull request 使用 smoke；排程固定使用 full；手動 workflow 可
選擇 smoke 或 full。
