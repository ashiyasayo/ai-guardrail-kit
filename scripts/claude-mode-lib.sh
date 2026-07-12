#!/usr/bin/env bash
# Scope-aware Claude Code plugin state helpers.

AGK_CLAUDE_MARKETPLACE=ai-guardrail-kit
AGK_CLAUDE_MODES=(decomposition-gate harness integrated-harness)

agk_claude_modes() { printf '%s\n' "${AGK_CLAUDE_MODES[@]}"; }

agk_claude_validate_scope() {
  case ${1:-} in project|local) return 0;; *) printf 'claude mode: unsupported scope: %s\n' "${1:-}" >&2; return 1;; esac
}

agk_claude_list_scope() {
  local scope=${1:-} listing result
  agk_claude_validate_scope "$scope" || return 1
  listing=$(mktemp "${TMPDIR:-/tmp}/ai-guardrail-claude-list.XXXXXX") || return 1
  if ! claude plugin list --json >"$listing"; then rm -f "$listing"; return 1; fi
  python3 - "$listing" "$scope" "$AGK_CLAUDE_MARKETPLACE" "${AGK_CLAUDE_MODES[@]}" <<'PY'
import json, pathlib, sys
path, wanted_scope, marketplace, *managed_names = sys.argv[1:]
try:
    data = json.loads(pathlib.Path(path).read_text())
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
if not isinstance(data, list):
    raise SystemExit(1)
managed = set(managed_names)
found = set()
for item in data:
    if not isinstance(item, dict):
        raise SystemExit(1)
    plugin_id, scope, enabled = item.get("id"), item.get("scope"), item.get("enabled")
    if not isinstance(plugin_id, str) or not isinstance(scope, str) or not isinstance(enabled, bool):
        raise SystemExit(1)
    if scope not in {"project", "local", "user"}:
        raise SystemExit(1)
    if "@" not in plugin_id:
        continue
    name, source = plugin_id.rsplit("@", 1)
    if scope == wanted_scope and enabled and source == marketplace and name in managed:
        found.add(name)
print("\n".join(sorted(found)))
PY
  result=$?
  rm -f "$listing"
  return "$result"
}

agk_claude_is_enabled() {
  local mode=${1:-} scope=${2:-} current listing
  case " ${AGK_CLAUDE_MODES[*]} " in *" $mode "*) :;; *) return 1;; esac
  listing=$(agk_claude_list_scope "$scope") || return 1
  while IFS= read -r current; do [[ $current == "$mode" ]] && return 0; done <<< "$listing"
  return 1
}

agk_claude_effective_modes() {
  local project local
  project=$(agk_claude_list_scope project) || return 1
  local=$(agk_claude_list_scope local) || return 1
  printf '%s\n%s\n' "$project" "$local" | awk 'NF && !seen[$0]++' | sort
}
