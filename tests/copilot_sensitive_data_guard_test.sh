#!/usr/bin/env bash
#
# 根層回歸入口：執行 Copilot sensitive-data-guard 的模式內 smoke test。
# 測試邏輯只維護一份（在模式目錄內），此處僅負責讓 tests/run_all.sh 與 CI 涵蓋它。
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$repo/copilot/plugins/sensitive-data-guard/tests/smoke_test.sh"
