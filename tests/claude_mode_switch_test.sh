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
reset_state() { rm -f "$AI_GUARDRAIL_CLAUDE_TEST_STATE"/*.json "$AI_GUARDRAIL_CLAUDE_TEST_STATE"/*.log "$AI_GUARDRAIL_CLAUDE_TEST_STATE"/delay.*; }
install() { claude plugin install "$1@ai-guardrail-kit" --scope "$2" >/dev/null; }
enable() { claude plugin enable "$1@ai-guardrail-kit" --scope "$2" >/dev/null; }

group=${1:-state}
[[ $group == state || $group == lifecycle ]] || fail "unknown test group: $group"
# shellcheck source=../scripts/claude-mode-lib.sh
source "$repo/scripts/claude-mode-lib.sh"

if [[ $group == lifecycle ]]; then
  project="$tmp/project"; mkdir -p "$project"; project=$(cd "$project" && pwd -P)
  (cd "$project" && claude plugin marketplace add "$repo/claude" --scope project >/dev/null)
  select_mode() { "$repo/scripts/select-claude-mode" "$@" "$project"; }
  verify_mode() { "$repo/scripts/verify-claude-mode" "$@" "$project"; }
  assert_effective() { verify_mode "$1" >/dev/null || fail "effective mode is not $1"; }
  state_digest() { find "$AI_GUARDRAIL_CLAUDE_TEST_STATE" -type f -name '*.json' -maxdepth 1 -print0 | sort -z | xargs -0 shasum -a 256 2>/dev/null || true; }
  managed_state() { python3 - "$AI_GUARDRAIL_CLAUDE_TEST_STATE" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); rows=[]
for scope in ('project','local'):
 p=root/f'{scope}.json'
 for x in json.loads(p.read_text()) if p.exists() else []:
  if x['id'].endswith('@ai-guardrail-kit') and x['id'].split('@')[0] in ('decomposition-gate','harness','integrated-harness'):
   rows.append((x['id'],scope,x['enabled']))
print(rows)
PY
  }

  reset_state
  before=$(state_digest)
  ! select_mode bogus >/dev/null 2>&1 || fail 'invalid mode accepted'
  ! select_mode harness --scope user >/dev/null 2>&1 || fail 'user scope accepted'
  [[ $before == "$(state_digest)" ]] || fail 'invalid input mutated state'

  output=$(select_mode decomposition-gate); grep -Fq 'start a new Claude Code session' <<<"$output" || fail 'selection omitted session restart'
  assert_effective decomposition-gate
  [[ -f $AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json ]] || fail 'project was not the default scope'
  before=$(state_digest); verify_mode decomposition-gate >/dev/null
  [[ $before == "$(state_digest)" ]] || fail 'verifier mutated plugin state'
  output=$(select_mode decomposition-gate); grep -Fq 'start a new Claude Code session' <<<"$output" || fail 'update omitted session restart'
  assert_effective decomposition-gate
  for from in decomposition-gate harness integrated-harness; do
    for to in decomposition-gate harness integrated-harness; do
      [[ $from == "$to" ]] && continue
      reset_state; select_mode "$from" >/dev/null; select_mode "$to" >/dev/null; assert_effective "$to"
    done
  done

  reset_state; install harness project; enable harness project; install decomposition-gate local; enable decomposition-gate local
  select_mode harness --scope project >/dev/null; assert_effective harness
  [[ $(agk_claude_list_scope local) == '' ]] || fail 'local conflict survived project selection'
  reset_state; install harness project; enable harness project; install decomposition-gate local; enable decomposition-gate local
  select_mode decomposition-gate --scope local >/dev/null; assert_effective decomposition-gate
  [[ $(agk_claude_list_scope project) == '' ]] || fail 'project conflict survived local selection'
  install decomposition-gate project; enable decomposition-gate project
  select_mode decomposition-gate --scope local >/dev/null
  [[ $(agk_claude_list_scope project) == '' ]] || fail 'duplicate target copy survived'

  install unrelated@elsewhere project; enable unrelated@elsewhere project
  output=$(select_mode --remove)
  grep -Fq 'start a new Claude Code session' <<<"$output" || fail 'remove omitted session restart'
  verify_mode --no-managed-mode >/dev/null || fail 'remove did not reach empty effective state'
  grep -Fq 'local' <<<"$output" || fail 'remove did not report changed local scope'
  grep -q 'unrelated@elsewhere' "$AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json" || fail 'unrelated plugin removed'

  reset_state; install harness project; enable harness project
  before=$(managed_state); export FAKE_CLAUDE_FAIL_INSTALL=integrated-harness
  output=$(select_mode integrated-harness 2>&1) && fail 'install failure accepted'
  unset FAKE_CLAUDE_FAIL_INSTALL
  grep -Fq 'selection failed; previous managed state restored' <<<"$output" || fail 'successful restoration wording missing'
  [[ $before == "$(managed_state)" ]] || fail 'install failure did not restore state'

  reset_state; install harness project; enable harness project
  before=$(managed_state); export FAKE_CLAUDE_FAIL_REMOVE=harness
  output=$(select_mode integrated-harness 2>&1) && fail 'remove failure accepted'
  unset FAKE_CLAUDE_FAIL_REMOVE
  grep -Fq 'selection failed; previous managed state restored' <<<"$output" || fail 'remove restoration wording missing'
  [[ $before == "$(managed_state)" ]] || fail 'remove failure did not restore state'

  reset_state; install harness project; enable harness project
  export FAKE_CLAUDE_FAIL_INSTALL=integrated-harness FAKE_CLAUDE_FAIL_ENABLE=harness
  output=$(select_mode integrated-harness 2>&1) && fail 'incomplete restoration accepted'
  unset FAKE_CLAUDE_FAIL_INSTALL FAKE_CLAUDE_FAIL_ENABLE
  grep -Fq 'selection failed; managed state restoration incomplete' <<<"$output" || fail 'incomplete restoration wording missing'

  reset_state; install harness project; enable harness project
  export FAKE_CLAUDE_COMMIT_THEN_FAIL_VERIFY=1
  output=$(select_mode harness 2>&1) && fail 'post-update verification failure accepted'
  unset FAKE_CLAUDE_COMMIT_THEN_FAIL_VERIFY
  grep -Fq 'update applied but verification failed' <<<"$output" || fail 'commit-point wording missing'

  export FAKE_CLAUDE_LIST_OUTPUT='{bad'
  output=$(verify_mode harness 2>&1) && fail 'malformed listing accepted by verifier'
  grep -Fq 'malformed Claude plugin state' <<<"$output" || fail 'malformed listing misdiagnosed'
  unset FAKE_CLAUDE_LIST_OUTPUT

  reset_state; install harness project; enable harness project; : > "$AI_GUARDRAIL_CLAUDE_TEST_STATE/calls.log"
  verify_mode harness >/dev/null || fail 'single-snapshot verifier rejected valid state'
  [[ $(grep -c $'\tplugin list --json$' "$AI_GUARDRAIL_CLAUDE_TEST_STATE/calls.log") -eq 1 ]] || fail 'verifier listed Claude state more than once'

  reset_state; elsewhere="$tmp/elsewhere"; mkdir -p "$elsewhere"
  export FAKE_CLAUDE_REQUIRE_PROJECT_CWD="$project"
  (cd "$elsewhere" && select_mode harness >/dev/null)
  unset FAKE_CLAUDE_REQUIRE_PROJECT_CWD
  awk -F '\t' -v project="$project" '$1 != project { print "unexpected cwd: " $0 > "/dev/stderr"; exit 1 }' "$AI_GUARDRAIL_CLAUDE_TEST_STATE/calls.log" || fail 'Claude operation ran outside project cwd'

  export FAKE_CLAUDE_LIST_OUTPUT='[{"id":"harness@ai-guardrail-kit","scope":"user","enabled":false}]'
  ! verify_mode harness >/dev/null 2>&1 || fail 'named verifier accepted managed user scope'
  ! verify_mode --no-managed-mode >/dev/null 2>&1 || fail 'empty verifier accepted managed user scope'
  unset FAKE_CLAUDE_LIST_OUTPUT

  for conflict_scope in project local; do
    export FAKE_CLAUDE_LIST_OUTPUT="[{\"id\":\"harness@ai-guardrail-kit\",\"scope\":\"project\",\"enabled\":true},{\"id\":\"decomposition-gate@ai-guardrail-kit\",\"scope\":\"$conflict_scope\",\"enabled\":false}]"
    output=$(verify_mode harness 2>&1) && fail "disabled $conflict_scope non-target accepted"
    grep -Fq "conflict: decomposition-gate ($conflict_scope)" <<<"$output" || fail "disabled $conflict_scope conflict diagnostic missing"
    unset FAKE_CLAUDE_LIST_OUTPUT
  done

  for missing in list install update uninstall enable disable marketplace; do
    reset_state; export FAKE_CLAUDE_MISSING_SUBCOMMAND=$missing
    output=$(select_mode harness 2>&1) && fail "missing $missing capability accepted"
    unset FAKE_CLAUDE_MISSING_SUBCOMMAND
    [[ ! -e $AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json && ! -e $AI_GUARDRAIL_CLAUDE_TEST_STATE/local.json ]] || fail "missing $missing capability mutated lifecycle state"
  done
  reset_state; export FAKE_CLAUDE_UNREGISTERED_MARKETPLACE=1
  output=$(select_mode harness 2>&1) && fail 'unregistered marketplace accepted'
  unset FAKE_CLAUDE_UNREGISTERED_MARKETPLACE
  [[ ! -e $AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json && ! -e $AI_GUARDRAIL_CLAUDE_TEST_STATE/local.json ]] || fail 'unregistered marketplace mutated lifecycle state'

  expected_marketplace=$(cd "$repo/claude" && pwd -P)
  assert_bad_marketplace_resolution() {
    local label=$1 listing=$2
    reset_state; export FAKE_CLAUDE_MARKETPLACE_LIST_OUTPUT=$listing
    output=$(select_mode harness 2>&1) && fail "$label marketplace resolution accepted"
    unset FAKE_CLAUDE_MARKETPLACE_LIST_OUTPUT
    [[ ! -e $AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json && ! -e $AI_GUARDRAIL_CLAUDE_TEST_STATE/local.json ]] || fail "$label marketplace resolution mutated lifecycle state"
  }
  assert_bad_marketplace_resolution wrong-source '[{"name":"ai-guardrail-kit","source":"/tmp/wrong","scope":"project"}]'
  assert_bad_marketplace_resolution missing-source '[{"name":"ai-guardrail-kit","scope":"project"}]'
  assert_bad_marketplace_resolution malformed-source '[{"name":"ai-guardrail-kit","source":7,"scope":"project"}]'
  assert_bad_marketplace_resolution duplicate-same-scope "[{\"name\":\"ai-guardrail-kit\",\"source\":\"$expected_marketplace\",\"scope\":\"project\"},{\"name\":\"ai-guardrail-kit\",\"source\":\"$expected_marketplace\",\"scope\":\"project\"}]"
  assert_bad_marketplace_resolution local-shadows-project "[{\"name\":\"ai-guardrail-kit\",\"source\":\"$expected_marketplace\",\"scope\":\"project\"},{\"name\":\"ai-guardrail-kit\",\"source\":\"/tmp/wrong\",\"scope\":\"local\"}]"
  reset_state
  export FAKE_CLAUDE_MARKETPLACE_LIST_OUTPUT="[{\"name\":\"ai-guardrail-kit\",\"source\":\"/tmp/wrong\",\"scope\":\"project\"},{\"name\":\"ai-guardrail-kit\",\"source\":\"$expected_marketplace\",\"scope\":\"local\"}]"
  select_mode harness >/dev/null || fail 'correct local marketplace did not take precedence over project'
  unset FAKE_CLAUDE_MARKETPLACE_LIST_OUTPUT

  bad_repo="$tmp/bad-repo"; cp -R "$repo" "$bad_repo"; printf '{bad\n' > "$bad_repo/claude/plugins/harness/hooks/hooks.json"
  reset_state
  ! "$bad_repo/scripts/select-claude-mode" harness "$project" >/dev/null 2>&1 || fail 'malformed package accepted'
  [[ ! -e $AI_GUARDRAIL_CLAUDE_TEST_STATE/calls.log ]] || ! grep -Eq $'\tplugin (install|update|uninstall|enable|disable) ' "$AI_GUARDRAIL_CLAUDE_TEST_STATE/calls.log" || fail 'malformed package reached lifecycle operation'
  for defect in marketplace manifest registration resource; do
    bad_repo="$tmp/bad-$defect"; cp -R "$repo" "$bad_repo"
    case $defect in
      marketplace) printf '{bad\n' > "$bad_repo/claude/.claude-plugin/marketplace.json";;
      manifest) rm "$bad_repo/claude/plugins/harness/.claude-plugin/plugin.json";;
      registration) printf '{"hooks":{}}\n' > "$bad_repo/claude/plugins/harness/hooks/hooks.json";;
      resource) rm "$bad_repo/claude/plugins/harness/hooks/plan_gate.py";;
    esac
    reset_state
    ! "$bad_repo/scripts/select-claude-mode" harness "$project" >/dev/null 2>&1 || fail "$defect package defect accepted"
    [[ ! -e $AI_GUARDRAIL_CLAUDE_TEST_STATE/calls.log ]] || ! grep -Eq $'\tplugin (install|update|uninstall|enable|disable) ' "$AI_GUARDRAIL_CLAUDE_TEST_STATE/calls.log" || fail "$defect package defect reached lifecycle operation"
  done
  for defect in wrong-source duplicate-name; do
    bad_repo="$tmp/bad-$defect"; cp -R "$repo" "$bad_repo"
    python3 - "$bad_repo/claude/.claude-plugin/marketplace.json" "$defect" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); data=json.loads(p.read_text()); defect=sys.argv[2]
entry=next(x for x in data['plugins'] if x['name']=='harness')
if defect=='wrong-source': entry['source']='./plugins/integrated-harness'
else: data['plugins'].append({'name':'harness','source':'./plugins/integrated-harness'})
p.write_text(json.dumps(data))
PY
    reset_state
    ! "$bad_repo/scripts/select-claude-mode" harness "$project" >/dev/null 2>&1 || fail "$defect selector package accepted"
    [[ ! -e $AI_GUARDRAIL_CLAUDE_TEST_STATE/calls.log ]] || ! grep -Eq $'\tplugin (install|update|uninstall|enable|disable) ' "$AI_GUARDRAIL_CLAUDE_TEST_STATE/calls.log" || fail "$defect selector reached lifecycle mutation"
    ! "$bad_repo/scripts/verify-claude-mode" harness "$project" >/dev/null 2>&1 || fail "$defect verifier package accepted"
  done

  reset_state; install harness project
  export FAKE_CLAUDE_INSTALL_ENABLED=1 FAKE_CLAUDE_FAIL_INSTALL=integrated-harness
  output=$(select_mode integrated-harness 2>&1) && fail 'disabled restoration setup accepted'
  unset FAKE_CLAUDE_INSTALL_ENABLED FAKE_CLAUDE_FAIL_INSTALL
  python3 - "$AI_GUARDRAIL_CLAUDE_TEST_STATE/project.json" <<'PY' || fail 'disabled tuple restored enabled'
import json,sys
x=json.load(open(sys.argv[1])); raise SystemExit(0 if len(x)==1 and x[0]['id'].startswith('harness@') and not x[0]['enabled'] else 1)
PY

  run_signal_case() { local phase=$1 sig=$2 expected=$3 output=$4 delay ready
    [[ $phase == pre ]] && delay=uninstall || delay=post-commit
    ready="$AI_GUARDRAIL_CLAUDE_TEST_STATE/delay.$delay.ready"
    FAKE_CLAUDE_DELAY_OPERATION=$([[ $phase == pre ]] && printf uninstall || printf none) \
    AI_GUARDRAIL_CLAUDE_TEST_PAUSE_AFTER_COMMIT=$([[ $phase == post ]] && printf '%s/delay.post-commit' "$AI_GUARDRAIL_CLAUDE_TEST_STATE" || printf '') \
    python3 - "$repo/scripts/select-claude-mode" "$([[ $phase == pre ]] && printf integrated-harness || printf harness)" "$project" "$ready" "$AI_GUARDRAIL_CLAUDE_TEST_STATE/delay.$delay.release" "$sig" "$expected" "$output" <<'PY'
import os,pathlib,signal,subprocess,sys,time
cmd,mode,project,ready,release,sig,expected,out=sys.argv[1:]
with open(out,'wb') as stream: p=subprocess.Popen([cmd,mode,project],stdout=stream,stderr=subprocess.STDOUT,env=os.environ.copy())
for _ in range(200):
 if pathlib.Path(ready).exists(): break
 if p.poll() is not None: raise SystemExit(1)
 time.sleep(.01)
else: p.kill(); raise SystemExit(1)
p.send_signal(getattr(signal,'SIG'+sig)); pathlib.Path(release).touch()
raise SystemExit(0 if p.wait()==int(expected) else 1)
PY
  }
  for sig_case in INT:130 TERM:143 HUP:129; do
    sig=${sig_case%%:*}; expected=${sig_case#*:}; reset_state; install harness project; enable harness project
    run_signal_case pre "$sig" "$expected" "$tmp/pre-$sig.out"; assert_effective harness
    reset_state; install harness project; enable harness project
    run_signal_case post "$sig" "$expected" "$tmp/post-$sig.out"
    grep -Fq 'update applied but verification interrupted' "$tmp/post-$sig.out" || fail "$sig post-commit wording missing"
  done
  printf 'PASS: transactional Claude mode switching\n'; exit 0
fi

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
