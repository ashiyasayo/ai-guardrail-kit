#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
cmp -s "$root/scripts/codex-runtime-manager.py" "$root/codex/plugins/ai-guardrail-loader/hooks/manager.py"
cmp -s "$root/scripts/select-codex-mode" "$root/codex/plugins/ai-guardrail-loader/hooks/select-codex-mode"
cmp -s "$root/scripts/verify-codex-mode" "$root/codex/plugins/ai-guardrail-loader/hooks/verify-codex-mode"
cmp -s "$root/scripts/install-codex-guardrail-loader" "$root/codex/plugins/ai-guardrail-loader/hooks/install-codex-guardrail-loader"
cmp -s "$root/scripts/prune-codex-runtime-cache" "$root/codex/plugins/ai-guardrail-loader/hooks/prune-codex-runtime-cache"
printf 'PASS: Codex loader bootstrap copies\n'
