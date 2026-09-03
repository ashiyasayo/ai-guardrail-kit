#!/usr/bin/env bash
set -euo pipefail
export PYTHONUTF8=${PYTHONUTF8:-1}
root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/project-a/.codex" "$tmp/project-b/.codex"
cp "$root/tests/helpers/fake-codex" "$tmp/bin/codex"
chmod +x "$tmp/bin/codex"
export PATH="$tmp/bin:$PATH" HOME="$tmp/home" CODEX_HOME="$tmp/home/.codex" AI_GUARDRAIL_TEST_STATE="$tmp/fake-state"
export MANAGER="$root/scripts/codex-runtime-manager.py"
export AI_GUARDRAIL_ALLOW_DEVELOPMENT_SOURCE=1
export AI_GUARDRAIL_MANIFEST_PATH="$tmp/manifest.json" AI_GUARDRAIL_ARCHIVE_DIR="$tmp/archives"

python3 - <<'PY'
import hashlib, json, os, tarfile, io
from pathlib import Path
out = Path(os.environ['AI_GUARDRAIL_ARCHIVE_DIR'])
out.mkdir()
commit = '1' * 40
modes = ('decomposition-gate', 'sensitive-data-guard', 'harness', 'integrated-harness')
slots = {
    'decomposition-gate': {'pretool.decomposition': 'hooks/dispatch.py'},
    'sensitive-data-guard': {'pretool.security': 'hooks/dispatch.py', 'pretool.pii': 'hooks/dispatch.py', 'prompt.pii': 'hooks/dispatch.py'},
    'harness': {'pretool.plan': 'hooks/dispatch.py', 'pretool.security': 'hooks/dispatch.py', 'pretool.pii': 'hooks/dispatch.py', 'prompt.pii': 'hooks/dispatch.py'},
    'integrated-harness': {'pretool.plan': 'hooks/dispatch.py', 'pretool.security': 'hooks/dispatch.py', 'pretool.pii': 'hooks/dispatch.py', 'prompt.pii': 'hooks/dispatch.py', 'session.start': 'hooks/dispatch.py'},
}
manifest = {'schema_version': 1, 'release': {'source': 'https://github.com/ashiyasayo/ai-guardrail-kit', 'ref': 'test', 'commit': commit, 'runtime_version': 'test+' + commit[:8]}, 'modes': {}}
for mode in modes:
    name = 'codex-runtime-' + mode + '.tar.gz'
    archive = out / name
    script = ('import json\nprint(json.dumps({"mode": ' + repr(mode) + '}))\n').encode()
    with tarfile.open(archive, 'w:gz') as bundle:
        info = tarfile.TarInfo('hooks/dispatch.py')
        info.size = len(script)
        bundle.addfile(info, io.BytesIO(script))
        if mode == 'integrated-harness':
            policy = b'# test policy\n'
            info = tarfile.TarInfo('orchestration-policy.md')
            info.size = len(policy)
            bundle.addfile(info, io.BytesIO(policy))
    manifest['modes'][mode] = {'archive_url': 'https://github.com/ashiyasayo/ai-guardrail-kit/releases/download/test/' + name, 'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'archive_size': archive.stat().st_size, 'entrypoints': slots[mode]}
Path(os.environ['AI_GUARDRAIL_MANIFEST_PATH']).write_text(json.dumps(manifest), encoding='utf-8')
PY

# loader 安裝與 mode runtime 選擇分離；後續切換不得觸碰 fake Codex 的 plugin 集合。
"$root/codex/plugins/ai-guardrail-loader/hooks/install-codex-guardrail-loader" --plugin-root "$root/codex/plugins/ai-guardrail-loader" >/dev/null

"$root/scripts/select-codex-mode" harness --scope project --source local --ref test "$tmp/project-a" >/dev/null
"$root/scripts/select-codex-mode" integrated-harness --scope project --source local --ref test "$tmp/project-b" >/dev/null
"$root/scripts/verify-codex-mode" harness --scope project "$tmp/project-a" >/dev/null
"$root/scripts/verify-codex-mode" integrated-harness --scope project "$tmp/project-b" --offline >/dev/null
python3 - <<'PY'
import json, os
from pathlib import Path
for name, expected in (('project-a','harness'),('project-b','integrated-harness')):
    data=json.loads((Path(os.environ['AI_GUARDRAIL_TEST_STATE']).parent/name/'.codex/guardrail/runtime.json').read_text())
    assert data['mode'] == expected
PY

event_a=$(python3 - "$tmp/project-a" <<'PY'
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'hook_event_name': 'PreToolUse', 'tool_name': 'exec_command'}))
PY
)
event_b=$(python3 - "$tmp/project-b" <<'PY'
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'hook_event_name': 'PreToolUse', 'tool_name': 'exec_command'}))
PY
)
dispatch_a=$(printf '%s\n' "$event_a" | AI_GUARDRAIL_LOADER_SLOT=pretool.security python3 "$root/codex/plugins/ai-guardrail-loader/hooks/loader.py")
grep -Fq 'harness' <<<"$dispatch_a" || { printf 'FAIL: project-a dispatch: %s\n' "$dispatch_a" >&2; exit 1; }
dispatch_b=$(printf '%s\n' "$event_b" | AI_GUARDRAIL_LOADER_SLOT=pretool.security python3 "$root/codex/plugins/ai-guardrail-loader/hooks/loader.py")
grep -Fq 'integrated-harness' <<<"$dispatch_b" || { printf 'FAIL: project-b dispatch: %s\n' "$dispatch_b" >&2; exit 1; }

natural="$tmp/natural"
mkdir -p "$natural/.codex"
"$root/scripts/select-codex-mode" sensitive-data-guard --scope project --source local --ref test "$natural" >/dev/null
"$root/scripts/select-codex-mode" harness --scope project "$natural" >/dev/null
"$root/scripts/verify-codex-mode" harness --scope project "$natural" >/dev/null

before_b=$(sha256sum "$tmp/project-b/.codex/guardrail/runtime.json" | cut -d' ' -f1)
"$root/scripts/select-codex-mode" decomposition-gate --scope project --source local --ref test "$tmp/project-a" >/dev/null
[[ $before_b == "$(sha256sum "$tmp/project-b/.codex/guardrail/runtime.json" | cut -d' ' -f1)" ]]

fallback="$tmp/fallback"
mkdir -p "$fallback/.codex"
"$root/scripts/select-codex-mode" sensitive-data-guard --scope user --source local --ref test "$fallback" >/dev/null
"$root/scripts/select-codex-mode" integrated-harness --scope project --source local --ref test "$fallback" >/dev/null
"$root/scripts/select-codex-mode" harness --scope local --source local --ref test "$fallback" >/dev/null
fallback_event=$(python3 - "$fallback" <<'PY'
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'hook_event_name': 'PreToolUse', 'tool_name': 'exec_command'}))
PY
)
fallback_dispatch=$(printf '%s\n' "$fallback_event" | AI_GUARDRAIL_LOADER_SLOT=pretool.security python3 "$root/codex/plugins/ai-guardrail-loader/hooks/loader.py")
grep -Fq 'harness' <<<"$fallback_dispatch"
"$root/scripts/select-codex-mode" --remove --scope local "$fallback" >/dev/null
fallback_dispatch=$(printf '%s\n' "$fallback_event" | AI_GUARDRAIL_LOADER_SLOT=pretool.security python3 "$root/codex/plugins/ai-guardrail-loader/hooks/loader.py")
grep -Fq 'integrated-harness' <<<"$fallback_dispatch"
"$root/scripts/select-codex-mode" --remove --scope project "$fallback" >/dev/null
fallback_dispatch=$(printf '%s\n' "$fallback_event" | AI_GUARDRAIL_LOADER_SLOT=pretool.security python3 "$root/codex/plugins/ai-guardrail-loader/hooks/loader.py")
grep -Fq 'sensitive-data-guard' <<<"$fallback_dispatch"

legacy="$tmp/legacy"
mkdir -p "$legacy/.codex"
python3 - "$legacy/.codex/config.toml" "$root" <<'PY'
import pathlib, sys
target, root = map(pathlib.Path, sys.argv[1:])
hooks = root / 'codex/plugins/harness/hooks'
lines = ['legacy = true', '# ai-guardrail-kit:begin']
for event, matcher, name in (
    ('PreToolUse', 'exec_command|apply_patch', 'plan_gate.py'),
    ('PreToolUse', 'exec_command|apply_patch', 'security_guard.py'),
    ('PreToolUse', 'apply_patch', 'pii_guard.py'),
    ('UserPromptSubmit', None, 'pii_guard.py'),
):
    lines.append(f'[[hooks.{event}]]')
    if matcher:
        lines.append(f'matcher = "{matcher}"')
    lines.extend(['', f'[[hooks.{event}.hooks]]', 'type = "command"', f'command = "python -- {hooks / name}"', ''])
lines.append('# ai-guardrail-kit:end')
target.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
"$root/scripts/select-codex-mode" harness --scope project --source local --ref test "$legacy" >/dev/null
! grep -Fq '# ai-guardrail-kit:begin' "$legacy/.codex/config.toml"
grep -Fq 'legacy = true' "$legacy/.codex/config.toml"

before=$(sha256sum "$tmp/project-a/.codex/guardrail/runtime.json" | cut -d' ' -f1)
printf '%s\n' '{"schema_version":1,"release":{"source":"https://github.com/ashiyasayo/ai-guardrail-kit","ref":"test","commit":"1111111111111111111111111111111111111111","runtime_version":"test+11111111"},"modes":{}}' > "$tmp/bad-manifest.json"
if AI_GUARDRAIL_MANIFEST_PATH="$tmp/bad-manifest.json" "$root/scripts/select-codex-mode" --update harness --scope project --source local --ref test "$tmp/project-a" >/dev/null 2>&1; then exit 1; fi
after=$(sha256sum "$tmp/project-a/.codex/guardrail/runtime.json" | cut -d' ' -f1)
[[ $before == "$after" ]]
printf 'PASS: Codex runtime selector, A/B dispatch, offline and rollback boundary\n'
