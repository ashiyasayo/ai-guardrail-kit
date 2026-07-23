#!/usr/bin/env bash
# Scope-aware Claude Code plugin state helpers.

# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3
#（WindowsApps 的 python3 別名 stub 找得到卻不能執行），故以實際執行 -V 探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}

AGK_CLAUDE_MARKETPLACE=ai-guardrail-kit
AGK_CLAUDE_MODES=(decomposition-gate sensitive-data-guard harness integrated-harness)

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
# Windows 上 stdout 預設會將換行翻譯為 CRLF，重設為 LF 供 bash 讀取
sys.stdout.reconfigure(newline=chr(10))
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

agk_claude_validate_package() {
  local repo=${1:-} target=${2:-}
  python3 - "$repo/.claude-plugin/marketplace.json" "$repo/claude/plugins" "$target" "$AGK_CLAUDE_MARKETPLACE" <<'PY'
import ast, importlib.util, json, pathlib, re, sys
market_path, plugins_name, target, identity = sys.argv[1:]
# find_spec 不得掃到呼叫端目前目錄的同名檔案，先自 sys.path 移除
sys.path = [p for p in sys.path if p not in ("", str(pathlib.Path.cwd()))]

def imports_resolvable(entry):
    # guard 進入點以頂層 import 載入同目錄檢查模組，須連同驗證其存在
    pending, seen = [entry], set()
    while pending:
        path = pending.pop()
        if path in seen: continue
        seen.add(path)
        try: tree = ast.parse(path.read_text())
        except (OSError, UnicodeError, SyntaxError, ValueError): return False
        names = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import): names.update(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom):
                if node.level: return False
                if node.module: names.add(node.module.split(".")[0])
        for name in names:
            sibling = path.parent / f"{name}.py"
            if sibling.is_file(): pending.append(sibling)
            else:
                try: spec = importlib.util.find_spec(name)
                except (ImportError, ValueError): return False
                if spec is None: return False
    return True

try:
    market = json.loads(pathlib.Path(market_path).read_text())
    entries = market["plugins"]
except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError):
    raise SystemExit(1)
if market.get("name") != identity or not isinstance(entries, list): raise SystemExit(1)
wanted = [target] if target else ["decomposition-gate", "sensitive-data-guard", "harness", "integrated-harness"]
for mode in wanted:
    matches=[x for x in entries if isinstance(x,dict) and x.get("name")==mode]
    if len(matches)!=1 or matches[0].get("source")!=f"./claude/plugins/{mode}": raise SystemExit(1)
    root=pathlib.Path(plugins_name)/mode
    try:
        manifest=json.loads((root/".claude-plugin/plugin.json").read_text())
        hooks=json.loads((root/"hooks/hooks.json").read_text())
    except (OSError, UnicodeError, json.JSONDecodeError): raise SystemExit(1)
    if manifest.get("name")!=mode or not isinstance(hooks.get("hooks"),dict) or not hooks["hooks"]: raise SystemExit(1)
    registered=0
    for group in hooks["hooks"].values():
        if not isinstance(group,list): raise SystemExit(1)
        for rule in group:
            if not isinstance(rule,dict) or not isinstance(rule.get("hooks"),list): raise SystemExit(1)
            for hook in rule["hooks"]:
                if not isinstance(hook,dict) or hook.get("type")!="command" or not isinstance(hook.get("command"),str): raise SystemExit(1)
                refs=re.findall(r'\$\{CLAUDE_PLUGIN_ROOT\}/([^"\s]+)',hook["command"])
                if len(refs)!=1 or not (root/refs[0]).is_file(): raise SystemExit(1)
                if not imports_resolvable(root/refs[0]): raise SystemExit(1)
                registered+=1
    if not registered: raise SystemExit(1)
PY
}
