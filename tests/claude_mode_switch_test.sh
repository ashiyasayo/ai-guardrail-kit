#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"
ln -s "$repo/tests/helpers/fake-claude" "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"
export AI_GUARDRAIL_CLAUDE_TEST_STATE="$tmp/state"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_output() { local expected=$1; shift; local actual; actual=$("$@") || fail "command failed: $*"; [[ $actual == "$expected" ]] || fail "expected [$expected], got [$actual]"; }
reset_state() { rm -f "$AI_GUARDRAIL_CLAUDE_TEST_STATE"/*.json; }
install() { claude plugin install "$1@ai-guardrail-kit" --scope "$2" >/dev/null; }
enable() { claude plugin enable "$1@ai-guardrail-kit" --scope "$2" >/dev/null; }

[[ ${1:-state} == state ]] || fail "unknown test group: ${1:-}"
# shellcheck source=../scripts/claude-mode-lib.sh
source "$repo/scripts/claude-mode-lib.sh"

assert_output $'decomposition-gate\nharness\nintegrated-harness' agk_claude_modes
agk_claude_validate_scope project || fail 'project scope rejected'
agk_claude_validate_scope local || fail 'local scope rejected'
! agk_claude_validate_scope user >/dev/null 2>&1 || fail 'user scope accepted'

reset_state
assert_output '' agk_claude_list_scope project
assert_output '' agk_claude_effective_modes

install harness project; enable harness project
assert_output harness agk_claude_list_scope project
assert_output '' agk_claude_list_scope local
agk_claude_is_enabled harness project || fail 'project harness not enabled'
! agk_claude_is_enabled harness local || fail 'project harness leaked into local'
assert_output harness agk_claude_effective_modes

reset_state; install decomposition-gate local; enable decomposition-gate local
assert_output decomposition-gate agk_claude_list_scope local
assert_output decomposition-gate agk_claude_effective_modes

reset_state; install harness project; enable harness project; install harness local; enable harness local
assert_output harness agk_claude_effective_modes

reset_state; install integrated-harness project; enable integrated-harness project; install decomposition-gate local; enable decomposition-gate local
assert_output $'decomposition-gate\nintegrated-harness' agk_claude_effective_modes

claude plugin install unrelated@elsewhere --scope project >/dev/null
claude plugin enable unrelated@elsewhere --scope project >/dev/null
claude plugin install harness-extra@ai-guardrail-kit --scope project >/dev/null
claude plugin enable harness-extra@ai-guardrail-kit --scope project >/dev/null
assert_output integrated-harness agk_claude_list_scope project
! agk_claude_is_enabled harness project || fail 'harness-extra matched harness'

export FAKE_CLAUDE_CORRUPT_LIST=1
! agk_claude_list_scope project >/dev/null 2>&1 || fail 'malformed JSON accepted'
! agk_claude_effective_modes >/dev/null 2>&1 || fail 'malformed effective state accepted'
unset FAKE_CLAUDE_CORRUPT_LIST
export FAKE_CLAUDE_LIST_OUTPUT='not json'
! agk_claude_list_scope project >/dev/null 2>&1 || fail 'text output accepted'
unset FAKE_CLAUDE_LIST_OUTPUT
export FAKE_CLAUDE_LIST_OUTPUT='[{"id":"harness@ai-guardrail-kit","scope":"project"}]'
! agk_claude_list_scope project >/dev/null 2>&1 || fail 'missing enabled field accepted'
unset FAKE_CLAUDE_LIST_OUTPUT

# Exercise the fake lifecycle contract used by the transactional selector tests.
reset_state
marketplace="$tmp/marketplace"
claude plugin marketplace add "$marketplace" --scope project >/dev/null
claude plugin marketplace add "$marketplace" --scope local >/dev/null
[[ $(<"$AI_GUARDRAIL_CLAUDE_TEST_STATE/marketplace.project") == "$marketplace" ]] || fail 'project marketplace scope not recorded'
[[ $(<"$AI_GUARDRAIL_CLAUDE_TEST_STATE/marketplace.local") == "$marketplace" ]] || fail 'local marketplace scope not recorded'

install harness project; enable harness project
install decomposition-gate local; enable decomposition-gate local
assert_output harness agk_claude_list_scope project
assert_output decomposition-gate agk_claude_list_scope local
claude plugin update harness@ai-guardrail-kit --scope project >/dev/null
python3 - "$AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json" <<'PY' || fail 'update did not advance version or preserve enabled state'
import json, pathlib, sys
items = json.loads(pathlib.Path(sys.argv[1]).read_text())
raise SystemExit(0 if items == [{"enabled": True, "id": "harness@ai-guardrail-kit", "scope": "project", "version": "2"}] else 1)
PY
claude plugin disable harness@ai-guardrail-kit --scope project >/dev/null
! agk_claude_is_enabled harness project || fail 'disable retained enabled state'
assert_output decomposition-gate agk_claude_list_scope local
claude plugin uninstall harness@ai-guardrail-kit --scope project >/dev/null
assert_output '' agk_claude_list_scope project
assert_output decomposition-gate agk_claude_list_scope local
project_before=$(<"$AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json")
! claude plugin update harness@ai-guardrail-kit --scope project >/dev/null 2>&1 || fail 'update installed a missing plugin'
[[ $(<"$AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json") == "$project_before" ]] || fail 'failed update mutated state'

project_before=$(<"$AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json")
export FAKE_CLAUDE_FAIL_INSTALL=integrated-harness
! claude plugin install integrated-harness@ai-guardrail-kit --scope project >/dev/null 2>&1 || fail 'forced install failure succeeded'
unset FAKE_CLAUDE_FAIL_INSTALL
[[ $(<"$AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json") == "$project_before" ]] || fail 'failed install mutated state'

install harness project; enable harness project
project_before=$(<"$AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json")
export FAKE_CLAUDE_FAIL_REMOVE=harness
! claude plugin uninstall harness@ai-guardrail-kit --scope project >/dev/null 2>&1 || fail 'forced remove failure succeeded'
unset FAKE_CLAUDE_FAIL_REMOVE
[[ $(<"$AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json") == "$project_before" ]] || fail 'failed remove mutated state'

export FAKE_CLAUDE_COMMIT_THEN_FAIL_VERIFY=1
claude plugin update harness@ai-guardrail-kit --scope project >/dev/null
unset FAKE_CLAUDE_COMMIT_THEN_FAIL_VERIFY
! agk_claude_list_scope project >/dev/null 2>&1 || fail 'post-commit next list was not corrupted'
assert_output harness agk_claude_list_scope project

printf 'PASS: Claude scope state adapter\n'
