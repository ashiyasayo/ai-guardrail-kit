#!/usr/bin/env bash
#
# 驗證 Copilot plugin 內的 hook 副本與唯一審核來源 shared/copilot 沒有漂移。
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$repo/scripts/sync-copilot-hook-copies" --check
printf 'PASS: Copilot hook 副本與 shared/copilot 一致\n'
