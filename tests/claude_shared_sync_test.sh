#!/usr/bin/env bash
set -euo pipefail

# 守護 Claude 側 PII 規則 hook 的唯一審核來源 shared/claude 與 5 份發佈副本
# （3 個 plugin hooks 目錄 + 2 個 copy-in .claude/hooks 目錄）逐字節一致。
# 對稱 tests/codex_shared_sync_test.sh。以 bash 呼叫 sync 腳本，容忍發佈副本
# 尚未標記為可執行的情況（提交前建議 chmod +x scripts/sync-claude-hook-copies）。
repo=$(cd "$(dirname "$0")/.." && pwd -P)
bash "$repo/scripts/sync-claude-hook-copies" --check
printf 'PASS: Claude shared hook copies are synchronized\n'
