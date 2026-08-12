# Codex mode-switch 測試效能待辦

日期：2026-08-03

## 狀態

部分完成；已完成實際呼叫量測與第一輪低風險優化，剩餘成本仍待進一步定位。

`tests/codex_mode_switch_test.sh` 是目前最慢的 Codex 測試，歷史實測約
836–1,167 秒（約 14–19 分鐘）。`tests/codex_global_install_test.sh` 次慢，約
48–64 秒。

## 待辦

- [x] 量測 `codex_mode_switch_test.sh` 及其呼叫腳本的實際啟動次數與單次耗時。
- [ ] 根據量測結果定位目前剩餘時間的主要成本。
- [x] 只有取得硬數字後，才評估是否修改 `scripts/codex-mode-lib.sh` 或其他生產腳本。
- [x] 修改後重新執行回歸測試，記錄前後耗時與行為差異。

## 本輪量測與修改

在同一台 Windows／Git Bash 主機，以匯出的 Python wrapper 記錄單次啟動數：

| 呼叫 | 修改前 | 修改後 |
| --- | ---: | ---: |
| selector（四種模式） | 13–21 次 Python | 11 次 Python |
| verify（四種模式） | 7–11 次 Python | 5 次 Python |
| `codex_mode_switch_test.sh` | 1,004 秒 | 955 秒 |

修改內容是將同一次 hook render 的命令值批次交給單一 Python 行程，並把 verify 的
區塊擷取、TOML 解析及 hook 路徑檢查合併；未改變 selector 的交易邊界或 rollback 語意。
完整 Codex mode-switch 測試已通過。剩餘時間顯示 Python 啟動不是唯一主因，暫不憑推論
修改更多生產流程；後續一次完整 root `full` 回歸測得 1,132 秒，顯示單支專測結果會
受 Windows 主機 I/O 與背景負載影響，955 秒不應視為固定上限。

## 參考

- `tests/run_all.sh`：目前對單支測試設有 2,400 秒逾時上限。
- `.docs/vault/gotchas/2026-08-03-perf-estimate-unit-cost.md`：既有量測、已排除項目與分析限制。
