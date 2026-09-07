#!/usr/bin/env bash
set -euo pipefail
export PYTHONUTF8=${PYTHONUTF8:-1}
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
cp "$root/tests/helpers/fake-codex" "$tmp/bin/codex"; chmod +x "$tmp/bin/codex"
export PATH="$tmp/bin:$PATH" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" AI_GUARDRAIL_TEST_STATE="$tmp/state"
mkdir -p "$AI_GUARDRAIL_TEST_STATE"

plugin_id='ai-guardrail-loader@ai-guardrail-kit'
# 用固定的 FAKE_CODEX_LIST_JSON 直接指定 source.path 指向本機 checkout 既有的
# loader plugin 內容，不需要在 fake 裡真的模擬 sparse checkout。
export FAKE_CODEX_LIST_JSON="{\"installed\":[{\"pluginId\":\"$plugin_id\",\"name\":\"ai-guardrail-loader\",\"marketplaceName\":\"ai-guardrail-kit\",\"installed\":true,\"enabled\":true,\"source\":{\"source\":\"local\",\"path\":\"$root/codex/plugins/ai-guardrail-loader\"}},{\"pluginId\":\"other-plugin@other-fork\",\"name\":\"other-plugin\",\"marketplaceName\":\"other-fork\",\"installed\":true,\"enabled\":true,\"source\":{\"source\":\"local\",\"path\":\"$root/codex/plugins/ai-guardrail-loader\"}}]}"

# 情境 1：全新環境（尚未加過 marketplace／plugin）也要能一次成功——
# 第一次 marketplace remove 必然失敗（尚未加過），腳本要能容忍並繼續。
"$root/scripts/refresh-codex-guardrail-ref" v0.6.1
[[ $(<"$AI_GUARDRAIL_TEST_STATE/marketplace.ai-guardrail-kit.ref") == v0.6.1 ]]
grep -Fxq "$plugin_id" "$AI_GUARDRAIL_TEST_STATE/installed"
[[ -x "$CODEX_HOME/guardrail/bin/select-codex-mode" ]]
[[ -x "$CODEX_HOME/guardrail/bin/verify-codex-mode" ]]
grep -Fq 'loader.py' "$CODEX_HOME/hooks.json"
[[ ! -f "$AI_GUARDRAIL_TEST_STATE/marketplace_remove:ai-guardrail-kit.count" ]]

# 情境 2：已存在舊 marketplace／plugin 時，必須先移除再切到新 ref 重裝。
"$root/scripts/refresh-codex-guardrail-ref" v0.6.2
[[ $(<"$AI_GUARDRAIL_TEST_STATE/marketplace.ai-guardrail-kit.ref") == v0.6.2 ]]
[[ $(<"$AI_GUARDRAIL_TEST_STATE/marketplace_remove:ai-guardrail-kit.count") == 1 ]]
grep -Fxq "$plugin_id" "$AI_GUARDRAIL_TEST_STATE/installed"

# 情境 3：--repo/--marketplace/--plugin 可自訂，且都會傳到對應的 codex 呼叫。
"$root/scripts/refresh-codex-guardrail-ref" v1.0.0 \
  --repo https://example.invalid/other-fork.git --marketplace other-fork --plugin other-plugin
[[ $(<"$AI_GUARDRAIL_TEST_STATE/marketplace.other-fork.ref") == v1.0.0 ]]
[[ $(<"$AI_GUARDRAIL_TEST_STATE/marketplace.other-fork.url") == https://example.invalid/other-fork.git ]]
grep -Fxq 'other-plugin@other-fork' "$AI_GUARDRAIL_TEST_STATE/installed"

printf 'PASS: refresh-codex-guardrail-ref switches marketplace/plugin/loader ref\n'
