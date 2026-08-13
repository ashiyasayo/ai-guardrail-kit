#!/usr/bin/env bash
# Shared implementation for select-codex-mode and verify-codex-mode.

# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3
#（WindowsApps 的 python3 別名 stub 找得到卻不能執行），故以實際執行版本檢查探測後回退。
# 版本檢查與支援性檢查合併，避免每次 selector／verify 額外啟動一次 Python。
if python3 -c 'import sys; raise SystemExit(sys.version_info < (3, 9))' >/dev/null 2>&1; then
  AGK_PYTHON_BIN=python3
elif python -c 'import sys; raise SystemExit(sys.version_info < (3, 9))' >/dev/null 2>&1; then
  AGK_PYTHON_BIN=python
  python3() { python "$@"; }
else
  AGK_PYTHON_BIN=python3
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}

AGK_MODES=(decomposition-gate sensitive-data-guard harness integrated-harness)
AGK_MARKETPLACE=ai-guardrail-kit
AGK_BEGIN='# ai-guardrail-kit:begin'
AGK_END='# ai-guardrail-kit:end'
AGK_PERSONAL_POLICY_CREATED=0

agk_die() { printf 'codex mode: %s\n' "$*" >&2; return 1; }

agk_valid_mode() {
  case $1 in decomposition-gate|sensitive-data-guard|harness|integrated-harness) return 0;; *) return 1;; esac
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
  [[ ! -e $config ]] && return 0

  # 分隔符只含 ASCII；以 awk 逐位元組檢查可避免為了基本結構驗證啟動 Python，
  # 同時不會受 Windows code page 或計畫內容的 UTF-8 影響。
  local error
  error=$(awk -v begin="$AGK_BEGIN" -v end="$AGK_END" '
    function occurrences(text, needle, position, total) {
      total = 0
      while ((position = index(text, needle)) != 0) {
        total++
        text = substr(text, position + length(needle))
      }
      return total
    }
    {
      begin_count += occurrences($0, begin)
      end_count += occurrences($0, end)
      line = $0
      sub(/\r$/, "", line)
      if (line == begin) begin_line = NR
      if (line == end) end_line = NR
    }
    END {
      if (begin_count != end_count || begin_count > 1) {
        print "malformed managed block delimiters"
        exit 1
      }
      if (begin_count && (begin_line == 0 || end_line == 0)) {
        print "delimiters must each occupy a complete line"
        exit 1
      }
      if (begin_count && begin_line > end_line) {
        print "managed block end precedes begin"
        exit 1
      }
    }
  ' "$config") || {
    agk_die "$error"
    return 1
  }
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
  "$AGK_PYTHON_BIN" - "$AGK_MARKETPLACE" "$listing" <<'PY'
import json, pathlib, sys
# Windows 上 stdout 預設會將換行翻譯為 CRLF，重設為 LF 供 bash 讀取
sys.stdout.reconfigure(newline=chr(10))
market = sys.argv[1]
managed = {"decomposition-gate", "sensitive-data-guard", "harness", "integrated-harness"}
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
  local mode=$1 repo=$2 root="$repo/codex/plugins/$1/hooks" rendered
  local command1 command2 command3 command4
  printf '%s\n' "$AGK_BEGIN"
  case $mode in
    decomposition-gate)
      rendered=$(agk_command_values "$root/decomposition_gate.py") || return 1
      IFS= read -r command1 <<< "$rendered"
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n' "$command1"
      ;;
    sensitive-data-guard)
      rendered=$(agk_command_values "$root/block_secrets.py" "$root/pii_guard.py") || return 1
      {
        IFS= read -r command1
        IFS= read -r command2
      } <<< "$rendered"
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n\n' "$command1"
      printf '[[hooks.PreToolUse]]\nmatcher = "apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n\n' "$command2"
      printf '[[hooks.UserPromptSubmit]]\n\n'
      printf '[[hooks.UserPromptSubmit.hooks]]\ntype = "command"\ncommand = %s\n' "$command2"
      ;;
    harness|integrated-harness)
      if [[ $mode == integrated-harness ]]; then
        rendered=$(agk_command_values "$root/plan_gate.py" "$root/security_guard.py" "$root/pii_guard.py" "$root/session_start.py") || return 1
      else
        rendered=$(agk_command_values "$root/plan_gate.py" "$root/security_guard.py" "$root/pii_guard.py") || return 1
      fi
      {
        IFS= read -r command1
        IFS= read -r command2
        IFS= read -r command3
        if [[ $mode == integrated-harness ]]; then
          IFS= read -r command4
        fi
      } <<< "$rendered"
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n\n' "$command1"
      printf '[[hooks.PreToolUse]]\nmatcher = "exec_command|apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n\n' "$command2"
      printf '[[hooks.PreToolUse]]\nmatcher = "apply_patch"\n\n'
      printf '[[hooks.PreToolUse.hooks]]\ntype = "command"\ncommand = %s\n\n' "$command3"
      printf '[[hooks.UserPromptSubmit]]\n\n'
      printf '[[hooks.UserPromptSubmit.hooks]]\ntype = "command"\ncommand = %s\n' "$command3"
      if [[ $mode == integrated-harness ]]; then
        printf '\n[[hooks.SessionStart]]\nmatcher = "startup|resume|clear|compact"\n\n'
        printf '[[hooks.SessionStart.hooks]]\ntype = "command"\ncommand = %s\n' "$command4"
      fi
      ;;
  esac
  printf '%s\n' "$AGK_END"
}

agk_command_values() {
  "$AGK_PYTHON_BIN" - "$AGK_PYTHON_BIN" "$@" <<'PY'
import json, shlex, sys
# Windows 上 stdout 預設會將換行翻譯為 CRLF，重設為 LF 供 bash 讀取
sys.stdout.reconfigure(newline=chr(10))
# sys.argv[0] 是 stdin 指令碼標記「-」；實際的直譯器與 hook 路徑從位置參數取得。
python_bin = sys.argv[1]
for path in sys.argv[2:]:
    print(json.dumps(python_bin + " -- " + shlex.quote(path)))
PY
}

agk_extract_managed_block() {
  local config=$1
  awk -v begin="$AGK_BEGIN" -v end="$AGK_END" '
    index($0, begin) { inside = 1 }
    inside { print }
    inside && index($0, end) { found = 1; exit }
    END { if (!found) exit 1 }
  ' "$config"
}

agk_verify_hook_files() {
  local mode=$1 repo=$2 root="$repo/codex/plugins/$mode/hooks" path
  local -a paths
  case $mode in
    decomposition-gate) paths=("$root/decomposition_gate.py");;
    sensitive-data-guard) paths=("$root/block_secrets.py" "$root/pii_guard.py");;
    harness) paths=("$root/plan_gate.py" "$root/security_guard.py" "$root/pii_guard.py");;
    integrated-harness) paths=("$root/plan_gate.py" "$root/security_guard.py" "$root/pii_guard.py" "$root/session_start.py");;
    *) agk_die "unknown managed mode: $mode"; return 1;;
  esac

  local exec_check
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) exec_check=0;; *) exec_check=1;; esac
  for path in "${paths[@]}"; do
    [[ -f $path ]] || { agk_die "hook file is missing: $path"; return 1; }
    (( ! exec_check )) || [[ -x $path ]] || { agk_die "hook file is not executable: $path"; return 1; }
  done
}

agk_verify_mode() {
  local expected=$1 project=$2 repo=$3 installed='' wanted_file='' mode count=0 line config actual wanted
  local installed_supplied=0
  if (( $# >= 4 )) && [[ -n ${4:-} ]]; then
    installed=$4
    installed_supplied=1
  fi
  if (( $# >= 5 )); then
    wanted_file=$5
  fi
  if (( ! installed_supplied )); then
    installed=$(agk_installed_modes) || { agk_die 'could not inspect installed plugins'; return 1; }
  fi
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    count=$((count + 1))
    [[ -n ${mode:-} ]] || mode=$line
  done <<< "$installed"
  (( count == 1 )) || { agk_die "expected exactly one installed managed plugin, found $count"; return 1; }
  [[ -z $expected || $expected == "$mode" ]] || { agk_die "installed mode $mode does not match expected $expected"; return 1; }
  AGK_VERIFIED_MODE=$mode
  if [[ $mode == integrated-harness ]]; then
    agk_validate_personal_policy || return 1
  fi

  config="$project/.codex/config.toml"
  [[ -f $config ]] || { agk_die 'managed config block is missing'; return 1; }
  agk_validate_config "$project" || return 1
  actual=$(agk_extract_managed_block "$config") || { agk_die 'managed hooks are malformed'; return 1; }
  if [[ -n $wanted_file ]]; then
    wanted=$(<"$wanted_file")
  else
    wanted=$(agk_render_block "$mode" "$repo") || return 1
  fi
  [[ $actual == "$wanted" ]] || { agk_die "managed hooks do not match installed mode $mode"; return 1; }
  agk_verify_hook_files "$mode" "$repo" || return 1
}

agk_verify_no_managed_mode() {
  local project=$1 installed count=0 line config
  if (( $# >= 2 )); then
    installed=$2
  else
    installed=$(agk_installed_modes) || { agk_die 'could not inspect installed plugins'; return 1; }
  fi
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    count=$((count + 1))
  done <<< "$installed"
  (( count == 0 )) || { agk_die "expected no installed managed plugin, found $count"; return 1; }
  agk_validate_config "$project" || return 1
  config="$project/.codex/config.toml"
  [[ ! -e $config ]] || ! grep -Fq "$AGK_BEGIN" "$config" || { agk_die 'managed config block remains'; return 1; }
}

agk_replace_config() {
  local project=$1 block_file=$2 config="$1/.codex/config.toml" tmp
  tmp=$(mktemp "$project/.codex/.config.toml.ai-guardrail.XXXXXX") || return 1
  if ! "$AGK_PYTHON_BIN" - "$config" "$tmp" "$block_file" "$AGK_BEGIN" "$AGK_END" <<'PY'
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
  if ! "$AGK_PYTHON_BIN" - "$config" "$tmp" "$AGK_BEGIN" "$AGK_END" <<'PY'
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
