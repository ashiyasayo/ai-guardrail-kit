# Codex mode-switch 測試效能待辦

日期：2026-08-03

## 狀態

已完成；已完成實際呼叫量測、兩輪低風險優化與完整專測驗證。

`tests/codex_mode_switch_test.sh` 是目前最慢的 Codex 測試，歷史實測約
836–1,167 秒（約 14–19 分鐘）。`tests/codex_global_install_test.sh` 次慢，約
48–64 秒。

## 待辦

- [x] 量測 `codex_mode_switch_test.sh` 及其呼叫腳本的實際啟動次數與單次耗時。
- [x] 根據量測結果定位目前剩餘時間的主要成本。
- [x] 只有取得硬數字後，才評估是否修改 `scripts/codex-mode-lib.sh` 或其他生產腳本。
- [x] 修改後重新執行回歸測試，記錄前後耗時與行為差異。

## 本輪量測與修改

在同一台 Windows／Git Bash 主機，以匯出的 Python wrapper 記錄單次啟動數：

| 呼叫 | 初始基準 | 第一輪後 | 第二輪後 |
| --- | ---: | ---: | ---: |
| selector（四種模式） | 13–21 次 Python | 11 次 Python | 5–6 次 Python |
| verify（四種模式） | 7–11 次 Python | 5 次 Python | 4–5 次 Python |
| `codex_mode_switch_test.sh` | 1,004 秒 | 955 秒 | 約 652 秒 |

第一輪將同一次 hook render 的命令值批次交給單一 Python 行程，並把 verify 的區塊
擷取、TOML 解析及 hook 路徑檢查合併。第二輪將 selector 內的 verify 改為同一個 Bash
流程，並以 `awk` 執行只涉及 ASCII 分隔符的設定檢查；驗證仍保留 TOML 產出、插件狀態、
個人政策、hook 檔案與 rollback 邊界，未改變交易語意。完整 Codex mode-switch 測試已
通過。量測顯示 Windows Git Bash 的程序與檔案 I/O 仍是剩餘成本，單支專測數字會受
主機背景負載影響，不應視為固定上限。

## 參考

- `tests/run_all.sh`：目前對單支測試設有 2,400 秒逾時上限。
- `.docs/vault/gotchas/2026-08-03-perf-estimate-unit-cost.md`：既有量測、已排除項目與分析限制。
