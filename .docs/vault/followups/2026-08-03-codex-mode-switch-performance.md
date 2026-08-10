# Codex mode-switch 測試效能待辦

日期：2026-08-03

## 狀態

待處理。

`tests/codex_mode_switch_test.sh` 是目前最慢的 Codex 測試，歷史實測約
836–1,167 秒（約 14–19 分鐘）。`tests/codex_global_install_test.sh` 次慢，約
48–64 秒。

## 待辦

- [ ] 量測 `codex_mode_switch_test.sh` 及其呼叫腳本的實際啟動次數與單次耗時。
- [ ] 根據量測結果定位剩餘約 836 秒的主要成本。
- [ ] 只有取得硬數字後，才評估是否修改 `scripts/codex-mode-lib.sh` 或其他生產腳本。
- [ ] 修改後重新執行回歸測試，記錄前後耗時與行為差異。

## 參考

- `tests/run_all.sh`：目前對單支測試設有 2,400 秒逾時上限。
- `.docs/vault/gotchas/2026-08-03-perf-estimate-unit-cost.md`：既有量測、已排除項目與分析限制。
