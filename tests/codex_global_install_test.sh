#!/usr/bin/env bash
set -euo pipefail
export PYTHONUTF8=${PYTHONUTF8:-1}
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/project/.codex"
cp "$root/tests/helpers/fake-codex" "$tmp/bin/codex"; chmod +x "$tmp/bin/codex"
export PATH="$tmp/bin:$PATH" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" AI_GUARDRAIL_TEST_STATE="$tmp/state"
export AI_GUARDRAIL_ALLOW_DEVELOPMENT_SOURCE=1 AI_GUARDRAIL_MANIFEST_PATH="$root/codex/runtime-manifest.json" AI_GUARDRAIL_ARCHIVE_DIR="$root/codex/runtime-archives"
printf 'unrelated@elsewhere\n' > "$tmp/state-seed"
mkdir -p "$AI_GUARDRAIL_TEST_STATE"; cp "$tmp/state-seed" "$AI_GUARDRAIL_TEST_STATE/installed"

# 直接從 marketplace plugin 自帶的 hook bootstrap，模擬沒有 repository checkout 的流程。
"$root/codex/plugins/ai-guardrail-loader/hooks/install-codex-guardrail-loader" --plugin-root "$root/codex/plugins/ai-guardrail-loader" >/dev/null
"$root/scripts/install-codex-global-integrated-harness" "$root" >/dev/null
"$root/scripts/verify-codex-global-integrated-harness" "$root" >/dev/null
grep -Fxq 'unrelated@elsewhere' "$AI_GUARDRAIL_TEST_STATE/installed"
grep -Fxq 'ai-guardrail-loader@ai-guardrail-kit' "$AI_GUARDRAIL_TEST_STATE/installed"
! grep -Eq '^(decomposition-gate|sensitive-data-guard|harness|integrated-harness)@' "$AI_GUARDRAIL_TEST_STATE/installed"
grep -Fq 'loader.py' "$CODEX_HOME/hooks.json"
grep -Fq 'AI_GUARDRAIL_LOADER_SLOT=pretool.security' "$CODEX_HOME/hooks.json"
grep -Fq 'AI_GUARDRAIL_LOADER_SLOT=session.start' "$CODEX_HOME/hooks.json"
[[ -x "$CODEX_HOME/guardrail/bin/prune-codex-runtime-cache" ]]

# marketplace upgrade 必須保留已安裝的 Loader 與其他使用者 plugin。
codex plugin marketplace upgrade ai-guardrail-kit
[[ $(<"$AI_GUARDRAIL_TEST_STATE/upgrade.args") == ai-guardrail-kit ]]
[[ $(<"$AI_GUARDRAIL_TEST_STATE/upgrade.count") == 1 ]]
grep -Fxq 'unrelated@elsewhere' "$AI_GUARDRAIL_TEST_STATE/installed"
grep -Fxq 'ai-guardrail-loader@ai-guardrail-kit' "$AI_GUARDRAIL_TEST_STATE/installed"

"$root/scripts/select-codex-mode" harness --scope project --source local --ref main "$tmp/project" >/dev/null
project_before=$(sha256sum "$tmp/project/.codex/guardrail/runtime.json" | cut -d' ' -f1)
"$root/scripts/install-codex-global-integrated-harness" --remove "$root" >/dev/null
"$root/scripts/verify-codex-global-integrated-harness" --no-installed "$root" >/dev/null
[[ $project_before == "$(sha256sum "$tmp/project/.codex/guardrail/runtime.json" | cut -d' ' -f1)" ]]
"$root/scripts/select-codex-mode" harness --scope user --source local --ref main "$root" >/dev/null
if "$root/scripts/install-codex-global-integrated-harness" --remove "$root" >/dev/null 2>&1; then
  printf 'FAIL: global wrapper removed an unowned user selector\n' >&2
  exit 1
fi
"$root/scripts/verify-codex-mode" harness --scope user "$root" >/dev/null
"$root/scripts/select-codex-mode" --remove --scope user "$root" >/dev/null
if "$root/codex/plugins/ai-guardrail-loader/hooks/install-codex-guardrail-loader" --plugin-root "$root/codex/plugins/ai-guardrail-loader" --remove >/dev/null 2>&1; then
  printf 'FAIL: loader removal ignored project selector\n' >&2
  exit 1
fi
grep -Fxq 'ai-guardrail-loader@ai-guardrail-kit' "$AI_GUARDRAIL_TEST_STATE/installed"
"$root/scripts/select-codex-mode" --remove --scope project "$tmp/project" >/dev/null
"$root/codex/plugins/ai-guardrail-loader/hooks/install-codex-guardrail-loader" --plugin-root "$root/codex/plugins/ai-guardrail-loader" --remove >/dev/null
! grep -Fxq 'ai-guardrail-loader@ai-guardrail-kit' "$AI_GUARDRAIL_TEST_STATE/installed"
printf 'PASS: global wrapper manages loader/user fallback only\n'
