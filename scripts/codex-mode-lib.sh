#!/usr/bin/env bash
# Shared implementation for select-codex-mode and verify-codex-mode.

AGK_MODES=(decomposition-gate harness integrated-harness)
AGK_MARKETPLACE=ai-guardrail-kit
AGK_BEGIN='# ai-guardrail-kit:begin'
AGK_END='# ai-guardrail-kit:end'

agk_die() { printf 'codex mode: %s\n' "$*" >&2; return 1; }

agk_valid_mode() {
  case $1 in decomposition-gate|harness|integrated-harness) return 0;; *) return 1;; esac
}

agk_resolve_project() {
  local requested=${1:-.}
  [[ -d $requested ]] || { agk_die "project directory does not exist: $requested"; return 1; }
  (cd "$requested" && pwd -P)
}

agk_validate_config() {
  local project=$1 config="$1/.codex/config.toml" codex_dir="$1/.codex"
  [[ -d $codex_dir && -w $codex_dir ]] || { agk_die "project .codex directory must exist and be writable: $codex_dir"; return 1; }
  if [[ -L $config ]]; then agk_die "refusing symlinked config: $config"; return 1; fi
  if [[ -e $config && ! -f $config ]]; then agk_die "refusing non-regular config: $config"; return 1; fi
  [[ ! -e $config || -r $config ]] || { agk_die "config is not readable: $config"; return 1; }
  python3 - "$config" "$AGK_BEGIN" "$AGK_END" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text() if p.exists() else ""
b, e = s.count(sys.argv[2]), s.count(sys.argv[3])
if b != e or b > 1:
    raise SystemExit("codex mode: malformed managed block delimiters")
lines = s.splitlines()
if b and (lines.count(sys.argv[2]) != 1 or lines.count(sys.argv[3]) != 1):
    raise SystemExit("codex mode: delimiters must each occupy a complete line")
if b and s.index(sys.argv[2]) > s.index(sys.argv[3]):
    raise SystemExit("codex mode: managed block end precedes begin")
PY
}

agk_installed_modes() {
  local listing
  listing=$(mktemp "${TMPDIR:-/tmp}/ai-guardrail-plugins.XXXXXX") || return 1
  if ! codex plugin list --json > "$listing"; then rm -f "$listing"; return 1; fi
  python3 - "$AGK_MARKETPLACE" "$listing" <<'PY'
import json, pathlib, sys
market = sys.argv[1]
managed = {"decomposition-gate", "harness", "integrated-harness"}
data = json.loads(pathlib.Path(sys.argv[2]).read_text())
for item in data.get("installed", []):
    if (item.get("installed", True) and item.get("enabled", True)
            and item.get("marketplaceName") == market
            and item.get("name") in managed):
        print(item["name"])
PY
  local result=$?
  rm -f "$listing"
  return $result
}

agk_render_block() {
  local mode=$1 repo=$2 root="$repo/codex/plugins/$1/hooks"
  printf '%s\n' "$AGK_BEGIN"
  case $mode in
    decomposition-gate)
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = "python3 %s/decomposition_gate.py"\n' "$root"
      ;;
    harness|integrated-harness)
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = "python3 %s/plan_gate.py"\n\n' "$root"
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = "python3 %s/block_dangerous_commands.py"\n\n' "$root"
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = "python3 %s/block_secrets.py"\n' "$root"
      ;;
  esac
  printf '%s\n' "$AGK_END"
}

agk_replace_config() {
  local project=$1 block_file=$2 config="$1/.codex/config.toml" tmp
  tmp=$(mktemp "$project/.codex/.config.toml.ai-guardrail.XXXXXX") || return 1
  if ! python3 - "$config" "$tmp" "$block_file" "$AGK_BEGIN" "$AGK_END" <<'PY'
import pathlib, sys
source, target, block_path = map(pathlib.Path, sys.argv[1:4])
begin, end = sys.argv[4:6]
old = source.read_bytes() if source.exists() else b""
block = block_path.read_bytes()
b, e = begin.encode(), end.encode()
if b in old:
    start = old.index(b)
    finish = old.index(e, start) + len(e)
    if finish < len(old) and old[finish:finish+2] == b"\r\n": finish += 2
    elif finish < len(old) and old[finish:finish+1] == b"\n": finish += 1
    new = old[:start] + block + old[finish:]
else:
    separator = b"" if not old or old.endswith((b"\n", b"\r\n")) else b"\n"
    new = old + separator + block
target.write_bytes(new)
PY
  then rm -f "$tmp"; return 1; fi
  if [[ ${AI_GUARDRAIL_TEST_FAIL_CONFIG_WRITE:-0} == 1 ]]; then rm -f "$tmp"; return 70; fi
  mv "$tmp" "$config"
}

agk_plugin_path() { printf '%s@%s' "$1" "$AGK_MARKETPLACE"; }
