#!/usr/bin/env bash
#
# 根層回歸入口：執行 Copilot decomposition-gate 的模式內 smoke test。
# 測試邏輯只維護一份（在模式目錄內），此處僅負責讓 tests/run_all.sh 與 CI 涵蓋它。
#
# 為何需要此包裝：該 smoke test 先前從未進入 CI，導致它在 Windows 上長期
# 假性通過（POSIX 臨時路徑經 stdin 傳入無法被 Windows Python 解析，造成普遍性
# deny，而寬鬆的斷言照樣是綠的）卻無人察覺。
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$repo/copilot/plugins/decomposition-gate/tests/smoke_test.sh"
