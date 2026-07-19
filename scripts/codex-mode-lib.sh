#!/usr/bin/env bash
# Shared implementation for select-codex-mode and verify-codex-mode.

# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3
#（WindowsApps 的 python3 別名 stub 找得到卻不能執行），故以實際執行 -V 探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}

AGK_MODES=(decomposition-gate harness integrated-harness)
AGK_MARKETPLACE=ai-guardrail-kit
AGK_BEGIN='# ai-guardrail-kit:begin'
AGK_END='# ai-guardrail-kit:end'
AGK_PERSONAL_POLICY_CREATED=0

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
  [[ ! -L $codex_dir && -d $codex_dir && -w $codex_dir ]] || { agk_die "project .codex directory must be a real writable directory: $codex_dir"; return 1; }
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

agk_personal_policy_path() {
  printf '%s\n' "$HOME/.codex/guardrail/orchestration-policy.md"
}

agk_validate_personal_policy() {
  local policy
  policy=$(agk_personal_policy_path)
  [[ ! -L $policy && -f $policy && -r $policy ]] || {
    agk_die "personal orchestration policy must be a readable regular file: $policy"
    return 1
  }
}

agk_install_personal_policy() {
  local repo=$1 source policy directory tmp
  source="$repo/codex/plugins/integrated-harness/orchestration-policy.md"
  policy=$(agk_personal_policy_path)
  directory=$(dirname "$policy")

  [[ -f $source && -r $source ]] || {
    agk_die "bundled orchestration policy is unavailable: $source"
    return 1
  }
  if [[ -e $policy || -L $policy ]]; then
    agk_validate_personal_policy
    return
  fi
  if [[ -e $directory && ( -L $directory || ! -d $directory ) ]]; then
    agk_die "personal guardrail directory must be a real directory: $directory"
    return 1
  fi
  mkdir -p "$directory" || return 1
  [[ -d $directory && ! -L $directory && -w $directory ]] || {
    agk_die "personal guardrail directory is not writable: $directory"
    return 1
  }
  tmp=$(mktemp "$directory/.orchestration-policy.XXXXXX") || return 1
  if ! cp -p "$source" "$tmp" || ! mv "$tmp" "$policy"; then
    rm -f "$tmp"
    return 1
  fi
  AGK_PERSONAL_POLICY_CREATED=1
}

agk_remove_created_personal_policy() {
  local repo=$1 source policy
  (( AGK_PERSONAL_POLICY_CREATED )) || return 0
  source="$repo/codex/plugins/integrated-harness/orchestration-policy.md"
  policy=$(agk_personal_policy_path)
  [[ ! -L $policy && -f $policy && -f $source ]] || return 1
  cmp -s "$source" "$policy" || return 1
  rm -f "$policy" || return 1
  AGK_PERSONAL_POLICY_CREATED=0
}

agk_installed_modes() {
  local listing
  listing=$(mktemp "${TMPDIR:-/tmp}/ai-guardrail-plugins.XXXXXX") || return 1
  if ! codex plugin list --json > "$listing"; then rm -f "$listing"; return 1; fi
  python3 - "$AGK_MARKETPLACE" "$listing" <<'PY'
import json, pathlib, sys
# Windows 上 stdout 預設會將換行翻譯為 CRLF，重設為 LF 供 bash 讀取
sys.stdout.reconfigure(newline=chr(10))
market = sys.argv[1]
managed = {"decomposition-gate", "harness", "integrated-harness"}
data = json.loads(pathlib.Path(sys.argv[2]).read_text())
if not isinstance(data, dict) or not isinstance(data.get("installed"), list): raise SystemExit(1)
seen = set()
for item in data["installed"]:
    if not isinstance(item, dict): raise SystemExit(1)
    name, plugin_id = item.get("name"), item.get("pluginId")
    relevant = item.get("marketplaceName") == market or name in managed or (isinstance(plugin_id, str) and plugin_id.endswith("@" + market))
    if not relevant: continue
    expected = f"{name}@{market}" if name in managed else None
    if (expected is None or plugin_id != expected or item.get("marketplaceName") != market
            or item.get("installed") is not True or item.get("enabled") is not True
            or name in seen): raise SystemExit(1)
    seen.add(name)
for name in sorted(seen): print(name)
PY
  local result=$?
  rm -f "$listing"
  return $result
}

agk_file_mode() {
  local path=$1 mode
  if mode=$(stat -f '%Lp' "$path" 2>/dev/null); then printf '%s\n' "$mode"; return 0; fi
  if mode=$(stat -c '%a' "$path" 2>/dev/null); then printf '%s\n' "$mode"; return 0; fi
  agk_die "could not determine file mode: $path"
}

agk_copy_mode() {
  local source=$1 target=$2 mode
  [[ ${AI_GUARDRAIL_TEST_FAIL_MODE_COPY:-0} != 1 ]] || return 1
  mode=$(agk_file_mode "$source") || return 1
  chmod "$mode" "$target"
}

agk_render_block() {
  local mode=$1 repo=$2 root="$repo/codex/plugins/$1/hooks"
  printf '%s\n' "$AGK_BEGIN"
  case $mode in
    decomposition-gate)
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n' "$(agk_command_value "$root/decomposition_gate.py")"
      ;;
    harness|integrated-harness)
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n\n' "$(agk_command_value "$root/plan_gate.py")"
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n\n' "$(agk_command_value "$root/block_dangerous_commands.py")"
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n' "$(agk_command_value "$root/block_secrets.py")"
      ;;
  esac
  printf '%s\n' "$AGK_END"
}

agk_command_value() {
  python3 - "$1" <<'PY'
import json, shlex, subprocess, sys
# Windows 上 stdout 預設會將換行翻譯為 CRLF，重設為 LF 供 bash 讀取
sys.stdout.reconfigure(newline=chr(10))
# 安裝當下解析可用的直譯器名稱，讓產生的 config 在 WSL 與 Windows 都能執行；
# 以實際執行 -V 探測，避免選到 Windows 上不能執行的 python3 別名 stub
def interpreter_is_usable(name):
    try:
        return subprocess.run([name, "-V"], capture_output=True).returncode == 0
    except OSError:
        return False
interpreter = "python3" if interpreter_is_usable("python3") else "python"
print(json.dumps(interpreter + " -- " + shlex.quote(sys.argv[1])))
PY
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
  agk_validate_config "$project" >/dev/null || { rm -f "$tmp"; return 1; }
  if [[ -e $config ]] && ! agk_copy_mode "$config" "$tmp"; then rm -f "$tmp"; return 1; fi
  mv "$tmp" "$config"
}

agk_remove_config_block() {
  local project=$1 config="$1/.codex/config.toml" tmp
  [[ -e $config ]] || return 0
  tmp=$(mktemp "$project/.codex/.config.toml.ai-guardrail.XXXXXX") || return 1
  if ! python3 - "$config" "$tmp" "$AGK_BEGIN" "$AGK_END" <<'PY'
import pathlib, sys
source, target = map(pathlib.Path, sys.argv[1:3]); begin, end = map(str.encode, sys.argv[3:5])
old = source.read_bytes()
if begin not in old:
    target.write_bytes(old); raise SystemExit
start = old.index(begin); finish = old.index(end, start) + len(end)
if finish < len(old) and old[finish:finish+2] == b"\r\n": finish += 2
elif finish < len(old) and old[finish:finish+1] == b"\n": finish += 1
target.write_bytes(old[:start] + old[finish:])
PY
  then rm -f "$tmp"; return 1; fi
  [[ ${AI_GUARDRAIL_TEST_FAIL_CONFIG_WRITE:-0} != 1 ]] || { rm -f "$tmp"; return 70; }
  agk_validate_config "$project" >/dev/null || { rm -f "$tmp"; return 1; }
  agk_copy_mode "$config" "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$config"
}


agk_restore_config() {
  local project=$1 snapshot=$2 existed=$3 config="$1/.codex/config.toml" tmp
  agk_validate_config "$project" >/dev/null || return 1
  if [[ $existed == 0 ]]; then rm -f "$config"; return; fi
  tmp=$(mktemp "$project/.codex/.config.toml.ai-guardrail.XXXXXX") || return 1
  cp -p "$snapshot" "$tmp" || { rm -f "$tmp"; return 1; }
  agk_validate_config "$project" >/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$config"
}

agk_plugin_path() { printf '%s@%s' "$1" "$AGK_MARKETPLACE"; }
