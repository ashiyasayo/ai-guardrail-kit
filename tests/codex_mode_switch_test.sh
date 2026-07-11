#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
ln -s "$repo/tests/helpers/fake-codex" "$tmp/bin/codex"
export PATH="$tmp/bin:$PATH"
export AI_GUARDRAIL_TEST_STATE="$tmp/state"
mkdir -p "$AI_GUARDRAIL_TEST_STATE"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file() { [[ -f $1 ]] || fail "missing $1"; }
assert_mode() { "$repo/scripts/verify-codex-mode" "$1" "$2" >/dev/null || fail "verify $1"; }
new_project() { local p=$1; mkdir -p "$p/.codex"; : > "$AI_GUARDRAIL_TEST_STATE/installed"; rm -f "$AI_GUARDRAIL_TEST_STATE"/*.count; }
assert_bad_json() { export FAKE_CODEX_LIST_JSON=$1; ! "$repo/scripts/verify-codex-mode" decomposition-gate "$project" >/dev/null 2>&1 || fail 'bad listing accepted'; unset FAKE_CODEX_LIST_JSON; }

project="$tmp/project"
new_project "$project"
printf 'prefix = "unchanged"\n\n# suffix stays too\n' > "$project/.codex/config.toml"
before=$(shasum -a 256 "$project/.codex/config.toml" "$AI_GUARDRAIL_TEST_STATE/installed")
if "$repo/scripts/select-codex-mode" bogus "$project" >/dev/null 2>&1; then fail 'invalid mode accepted'; fi
[[ $before == "$(shasum -a 256 "$project/.codex/config.toml" "$AI_GUARDRAIL_TEST_STATE/installed")" ]] || fail 'invalid mode mutated state'

"$repo/scripts/select-codex-mode" decomposition-gate "$project"
assert_mode decomposition-gate "$project"
grep -Fq 'prefix = "unchanged"' "$project/.codex/config.toml" || fail 'prefix changed'
grep -Fq '# suffix stays too' "$project/.codex/config.toml" || fail 'suffix changed'
first=$(shasum -a 256 "$project/.codex/config.toml" "$AI_GUARDRAIL_TEST_STATE/installed")
assert_bad_json '{"installed":[{"pluginId":"decomposition-gate@ai-guardrail-kit","name":"decomposition-gate","marketplaceName":"ai-guardrail-kit","installed":true,"enabled":false}]}'
assert_bad_json '{"installed":[{"pluginId":"wrong@ai-guardrail-kit","name":"decomposition-gate","marketplaceName":"ai-guardrail-kit","installed":true,"enabled":true}]}'
assert_bad_json '{"installed":[{"pluginId":"decomposition-gate@ai-guardrail-kit","name":"decomposition-gate","marketplaceName":"ai-guardrail-kit","installed":true,"enabled":true},{"pluginId":"decomposition-gate@ai-guardrail-kit","name":"decomposition-gate","marketplaceName":"ai-guardrail-kit","installed":true,"enabled":true}]}'
assert_bad_json '{"installed":"bad"}'
assert_bad_json '[]'
assert_bad_json '{}'
assert_bad_json '{"installed":["bad"]}'
assert_bad_json '{"installed":[{"pluginId":7,"name":"decomposition-gate","marketplaceName":"ai-guardrail-kit","installed":true,"enabled":true}]}'
"$repo/scripts/select-codex-mode" decomposition-gate "$project"
[[ $first == "$(shasum -a 256 "$project/.codex/config.toml" "$AI_GUARDRAIL_TEST_STATE/installed")" ]] || fail 'selection not idempotent'

for from in decomposition-gate harness integrated-harness; do
  for to in decomposition-gate harness integrated-harness; do
    if [[ $from == "$to" ]]; then continue; fi
    new_project "$tmp/trans-$from-$to"
    "$repo/scripts/select-codex-mode" "$from" "$tmp/trans-$from-$to" >/dev/null
    "$repo/scripts/select-codex-mode" "$to" "$tmp/trans-$from-$to" >/dev/null
    assert_mode "$to" "$tmp/trans-$from-$to"
  done
done

new_project "$tmp/malformed"
printf '# ai-guardrail-kit:begin\n# ai-guardrail-kit:begin\n# ai-guardrail-kit:end\n' > "$tmp/malformed/.codex/config.toml"
if "$repo/scripts/select-codex-mode" harness "$tmp/malformed" >/dev/null 2>&1; then fail 'duplicate delimiter accepted'; fi

new_project "$tmp/nonregular"
mkdir "$tmp/nonregular/.codex/config.toml"
if "$repo/scripts/select-codex-mode" harness "$tmp/nonregular" >/dev/null 2>&1; then fail 'non-regular config accepted'; fi

new_project "$tmp/symlink"
printf 'outside\n' > "$tmp/outside"
rm "$tmp/symlink/.codex/config.toml" 2>/dev/null || true
ln -s "$tmp/outside" "$tmp/symlink/.codex/config.toml"
if "$repo/scripts/select-codex-mode" harness "$tmp/symlink" >/dev/null 2>&1; then fail 'symlink accepted'; fi
[[ $(cat "$tmp/outside") == outside ]] || fail 'symlink target changed'
new_project "$tmp/codex-symlink"; rm -rf "$tmp/codex-symlink/.codex"; ln -s "$tmp" "$tmp/codex-symlink/.codex"
if "$repo/scripts/select-codex-mode" harness "$tmp/codex-symlink" >/dev/null 2>&1; then fail '.codex symlink accepted'; fi

special="$tmp/repo space 'quote' \\backslash \$(touch INJECTED) \`touch ALSO\`;touch SEMI"
cp -R "$repo" "$special"; new_project "$tmp/meta"
(cd "$tmp" && "$special/scripts/select-codex-mode" decomposition-gate "$tmp/meta" >/dev/null)
[[ ! -e "$tmp/INJECTED" && ! -e "$tmp/ALSO" && ! -e "$tmp/SEMI" ]] || fail 'path injection executed'
python3 - "$tmp/meta/.codex/config.toml" <<'PY' || fail 'invalid TOML rendering'
import sys, tomllib
tomllib.load(open(sys.argv[1], 'rb'))
PY

new_project "$tmp/rollback-add"
"$repo/scripts/select-codex-mode" harness "$tmp/rollback-add" >/dev/null
config_before=$(shasum -a 256 "$tmp/rollback-add/.codex/config.toml")
plugins_before=$(cat "$AI_GUARDRAIL_TEST_STATE/installed")
export FAKE_CODEX_FAIL_OPERATION=add FAKE_CODEX_FAIL_PLUGIN=integrated-harness@ai-guardrail-kit
if "$repo/scripts/select-codex-mode" integrated-harness "$tmp/rollback-add" >/dev/null 2>&1; then fail 'add failure accepted'; fi
unset FAKE_CODEX_FAIL_OPERATION FAKE_CODEX_FAIL_PLUGIN
[[ $config_before == "$(shasum -a 256 "$tmp/rollback-add/.codex/config.toml")" ]] || fail 'config not rolled back after add failure'
[[ $plugins_before == "$(cat "$AI_GUARDRAIL_TEST_STATE/installed")" ]] || fail 'plugins not rolled back after add failure'

export FAKE_CODEX_FAIL_OPERATION=remove FAKE_CODEX_FAIL_PLUGIN=harness@ai-guardrail-kit
if "$repo/scripts/select-codex-mode" decomposition-gate "$tmp/rollback-add" >/dev/null 2>&1; then fail 'remove failure accepted'; fi
unset FAKE_CODEX_FAIL_OPERATION FAKE_CODEX_FAIL_PLUGIN
[[ $config_before == "$(shasum -a 256 "$tmp/rollback-add/.codex/config.toml")" ]] || fail 'config changed after remove failure'
[[ $plugins_before == "$(cat "$AI_GUARDRAIL_TEST_STATE/installed")" ]] || fail 'plugins changed after remove failure'

new_project "$tmp/snapshot-copy"; printf 'snapshot-original\n' > "$tmp/snapshot-copy/.codex/config.toml"
export AI_GUARDRAIL_TEST_FAIL_SNAPSHOT_COPY=1
if "$repo/scripts/select-codex-mode" harness "$tmp/snapshot-copy" >/dev/null 2>&1; then fail 'snapshot copy failure accepted'; fi
unset AI_GUARDRAIL_TEST_FAIL_SNAPSHOT_COPY
[[ $(cat "$tmp/snapshot-copy/.codex/config.toml") == snapshot-original ]] || fail 'snapshot failure mutated config'
[[ ! -s $AI_GUARDRAIL_TEST_STATE/installed ]] || fail 'snapshot failure mutated plugins'

new_project "$tmp/rollback-write"
"$repo/scripts/select-codex-mode" harness "$tmp/rollback-write" >/dev/null
config_before=$(shasum -a 256 "$tmp/rollback-write/.codex/config.toml")
plugins_before=$(cat "$AI_GUARDRAIL_TEST_STATE/installed")
export AI_GUARDRAIL_TEST_FAIL_CONFIG_WRITE=1
if "$repo/scripts/select-codex-mode" integrated-harness "$tmp/rollback-write" >/dev/null 2>&1; then fail 'write failure accepted'; fi
unset AI_GUARDRAIL_TEST_FAIL_CONFIG_WRITE
[[ $config_before == "$(shasum -a 256 "$tmp/rollback-write/.codex/config.toml")" ]] || fail 'config not rolled back after write failure'
[[ $plugins_before == "$(cat "$AI_GUARDRAIL_TEST_STATE/installed")" ]] || fail 'plugins not rolled back after write failure'

new_project "$tmp/partial"; printf 'decomposition-gate@ai-guardrail-kit\nharness@ai-guardrail-kit\n' > "$AI_GUARDRAIL_TEST_STATE/installed"
export FAKE_CODEX_FAIL_OPERATION='remove:2'
if "$repo/scripts/select-codex-mode" integrated-harness "$tmp/partial" >/dev/null 2>&1; then fail 'partial remove accepted'; fi
unset FAKE_CODEX_FAIL_OPERATION
grep -Fxq decomposition-gate@ai-guardrail-kit "$AI_GUARDRAIL_TEST_STATE/installed" || fail 'partial rollback lost plugin'

new_project "$tmp/verify-rollback"; printf 'harness@ai-guardrail-kit\n' > "$AI_GUARDRAIL_TEST_STATE/installed"
printf 'verify-original\n' > "$tmp/verify-rollback/.codex/config.toml"
export FAKE_CODEX_FAIL_OPERATION='list:2'
if "$repo/scripts/select-codex-mode" integrated-harness "$tmp/verify-rollback" >/dev/null 2>&1; then fail 'verification failure accepted'; fi
unset FAKE_CODEX_FAIL_OPERATION
grep -Fxq harness@ai-guardrail-kit "$AI_GUARDRAIL_TEST_STATE/installed" || fail 'verification failure not rolled back'
[[ $(cat "$tmp/verify-rollback/.codex/config.toml") == verify-original ]] || fail 'verification config not rolled back'

new_project "$tmp/rollback-failure"; printf 'harness@ai-guardrail-kit\n' > "$AI_GUARDRAIL_TEST_STATE/installed"
export FAKE_CODEX_FAIL_OPERATION='add:2' AI_GUARDRAIL_TEST_FAIL_CONFIG_WRITE=1
output=$("$repo/scripts/select-codex-mode" integrated-harness "$tmp/rollback-failure" 2>&1) && fail 'rollback mutation failure accepted'
unset FAKE_CODEX_FAIL_OPERATION AI_GUARDRAIL_TEST_FAIL_CONFIG_WRITE
grep -Fq 'rollback also failed' <<<"$output" || fail 'rollback mutation failure not reported'

new_project "$tmp/mode"; printf 'mode-original\n' > "$tmp/mode/.codex/config.toml"; chmod 640 "$tmp/mode/.codex/config.toml"
"$repo/scripts/select-codex-mode" harness "$tmp/mode" >/dev/null
[[ $(stat -f '%Lp' "$tmp/mode/.codex/config.toml") == 640 ]] || fail 'forward write changed mode'

config_before=$(shasum -a 256 "$tmp/mode/.codex/config.toml"); plugins_before=$(cat "$AI_GUARDRAIL_TEST_STATE/installed")
export AI_GUARDRAIL_TEST_FAIL_MODE_COPY=1
if "$repo/scripts/select-codex-mode" integrated-harness "$tmp/mode" >/dev/null 2>&1; then fail 'mode copy failure accepted'; fi
unset AI_GUARDRAIL_TEST_FAIL_MODE_COPY
[[ $config_before == "$(shasum -a 256 "$tmp/mode/.codex/config.toml")" ]] || fail 'mode failure changed config'
[[ $plugins_before == "$(cat "$AI_GUARDRAIL_TEST_STATE/installed")" ]] || fail 'mode failure changed plugins'
[[ $(stat -f '%Lp' "$tmp/mode/.codex/config.toml") == 640 ]] || fail 'mode failure rollback changed mode'

new_project "$tmp/order"; printf 'harness@ai-guardrail-kit\ndecomposition-gate@ai-guardrail-kit\n' > "$AI_GUARDRAIL_TEST_STATE/installed"
export FAKE_CODEX_FAIL_OPERATION='remove:2'
output=$("$repo/scripts/select-codex-mode" integrated-harness "$tmp/order" 2>&1) && fail 'ordered rollback setup accepted'
unset FAKE_CODEX_FAIL_OPERATION
grep -Fq 'rollback succeeded' <<<"$output" || fail 'set-equivalent rollback order reported failure'

for signal_case in TERM:143 HUP:129; do
  signal=${signal_case%%:*}; expected=${signal_case#*:}
  new_project "$tmp/signal-$signal"; printf 'harness@ai-guardrail-kit\n' > "$AI_GUARDRAIL_TEST_STATE/installed"; printf 'signal-original\n' > "$tmp/signal-$signal/.codex/config.toml"
  FAKE_CODEX_DELAY_OPERATION=remove "$repo/scripts/select-codex-mode" integrated-harness "$tmp/signal-$signal" >/dev/null 2>&1 & pid=$!
  sleep 0.2; kill -"$signal" "$pid"; set +e; wait "$pid"; status=$?; set -e
  [[ $status -eq $expected ]] || fail "$signal status $status"
  grep -Fxq harness@ai-guardrail-kit "$AI_GUARDRAIL_TEST_STATE/installed" || fail "$signal plugin rollback failed"
  [[ $(cat "$tmp/signal-$signal/.codex/config.toml") == signal-original ]] || fail "$signal config rollback failed"
done

new_project "$tmp/signal-INT"; printf 'harness@ai-guardrail-kit\n' > "$AI_GUARDRAIL_TEST_STATE/installed"; printf 'signal-original\n' > "$tmp/signal-INT/.codex/config.toml"
FAKE_CODEX_DELAY_OPERATION=remove python3 - "$repo/scripts/select-codex-mode" "$tmp/signal-INT" <<'PY' || fail 'INT status or rollback failed'
import os, signal, subprocess, sys, time
p = subprocess.Popen([sys.argv[1], "integrated-harness", sys.argv[2]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(.2); p.send_signal(signal.SIGINT)
raise SystemExit(0 if p.wait() == 130 else 1)
PY
grep -Fxq harness@ai-guardrail-kit "$AI_GUARDRAIL_TEST_STATE/installed" || fail 'INT plugin rollback failed'
[[ $(cat "$tmp/signal-INT/.codex/config.toml") == signal-original ]] || fail 'INT config rollback failed'

printf 'unrelated@elsewhere\n' >> "$AI_GUARDRAIL_TEST_STATE/installed"
"$repo/scripts/select-codex-mode" decomposition-gate "$tmp/rollback-write" >/dev/null
grep -Fxq unrelated@elsewhere "$AI_GUARDRAIL_TEST_STATE/installed" || fail 'unrelated plugin removed'
sed -i.bak 's|decomposition-gate/hooks|harness/hooks|' "$tmp/rollback-write/.codex/config.toml"
if "$repo/scripts/verify-codex-mode" decomposition-gate "$tmp/rollback-write" >/dev/null 2>&1; then fail 'hook mismatch not detected'; fi

printf 'PASS: transactional Codex mode switching\n'
