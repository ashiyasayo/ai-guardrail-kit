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

printf 'PASS: Claude scope state adapter\n'
