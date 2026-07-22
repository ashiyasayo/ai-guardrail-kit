#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd -P)
"$repo/scripts/sync-codex-hook-copies" --check
printf 'PASS: Codex shared hook copies are synchronized\n'
