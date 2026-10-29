#!/usr/bin/env bash
set -euo pipefail
export PYTHONUTF8=${PYTHONUTF8:-1}
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, pathlib, re
root=pathlib.Path('.')
data=json.loads((root/'.agents/plugins/marketplace.json').read_text())
names=['ai-guardrail-loader','decomposition-gate','sensitive-data-guard','harness','integrated-harness']
assert data['name']=='ai-guardrail-kit'
assert [p['name'] for p in data['plugins']]==names
for plugin in data['plugins']:
    name=plugin['name']; base=root/plugin['source']['path'][2:]
    assert base.name==name and (base/'.codex-plugin/plugin.json').is_file()
    assert plugin['category']=='Security'
    policy=plugin['policy']['installation']
    assert policy == ('AVAILABLE' if name=='ai-guardrail-loader' else 'NOT_AVAILABLE')
    manifest=json.loads((base/'.codex-plugin/plugin.json').read_text())
    assert manifest['name']==name
    if name == 'ai-guardrail-loader':
        # loader 以 $CODEX_HOME/hooks.json 管理 hook；此欄位只能指向單一設定檔。
        assert 'hooks' not in manifest
    skills=list((base/'skills').glob('*/SKILL.md'))
    expected_skills = 6 if name == 'ai-guardrail-loader' else 1
    assert len(skills)==expected_skills, (name, [skill.parent.name for skill in skills])
    primary = base/'skills'/name/'SKILL.md'
    assert primary.is_file()
    assert ('new thread' in primary.read_text()) if name != 'ai-guardrail-loader' else True
loader=root/'codex/plugins/ai-guardrail-loader/hooks'
for name in ('loader.py','manager.py','select-codex-mode','verify-codex-mode','install-codex-guardrail-loader','prune-codex-runtime-cache','uninstall-codex-guardrail'):
    assert (loader/name).is_file(), name
manifest=json.loads((root/'codex/runtime-manifest.json').read_text())
assert manifest['schema_version']==2 and set(manifest['modes'])==set(names[1:])
assert 'commit' not in manifest['release']
for mode, item in manifest['modes'].items():
    assert re.fullmatch(r'[0-9a-f]{64}', item['archive_sha256'])
    assert item['archive_size'] > 0
    expected_path='codex/runtime-archives/codex-runtime-' + mode + '.tar.gz'
    assert item['archive_path'] == expected_path
    assert 'archive_url' not in item
    archive=root/item['archive_path']
    assert archive.is_file() and archive.stat().st_size == item['archive_size']
    assert __import__('hashlib').sha256(archive.read_bytes()).hexdigest() == item['archive_sha256']
    # archive 必須是目前審核來源，不能只與可能過期的 manifest 自洽。
    with __import__('tarfile').open(archive) as bundle:
        for member in bundle.getmembers():
            if member.isfile():
                source=root/'codex/plugins'/mode/member.name
                assert bundle.extractfile(member).read()==source.read_bytes(), (mode,member.name)
        if mode in ('harness','integrated-harness'):
            assert 'hooks/approval.py' in bundle.getnames()

guide=(root/'docs/codex-marketplace.md').read_text()
for needle in ('ai-guardrail-loader@ai-guardrail-kit','runtime.local.json','--offline','E_ARCHIVE_UNSAFE','shell=False','no-checkout','selector-index.json','--apply','## Complete uninstall','install-codex-guardrail-loader --plugin-root <plugin-directory> --remove','uninstall-codex-guardrail" --confirm --prune-cache'):
    assert needle in guide, needle
readme=(root/'README.md').read_text()
assert 'hook 熱路徑' in readme and 'ai-guardrail-loader' in readme
assert '完整解除安裝必須先移除每個仍在使用的' in readme
assert '### copy-in（Claude Code／GitHub Copilot）' in readme
cli_reference=(root/'CLI_REFERENCE.md').read_text()
for label, document in (('README', readme), ('CLI_REFERENCE', cli_reference), ('marketplace guide', guide)):
    assert re.search(r'\$guardrail_bin/select-codex-mode" integrated-harness --scope user --ref <40-hex-commit>\n', document), label
    assert not re.search(r'\$guardrail_bin/select-codex-mode" integrated-harness --scope user --ref <40-hex-commit>\s+/path/to/', document), label
for plugin in names[1:]:
    base = root/f'codex/plugins/{plugin}'
    skill = (base/'skills'/plugin/'SKILL.md').read_text()
    assert 'For `user` scope, omit `[project-dir]`' in skill, plugin
dg_manifest = json.loads((root/'codex/plugins/decomposition-gate/.codex-plugin/plugin.json').read_text())
dg_skill = (root/'codex/plugins/decomposition-gate/skills/decomposition-gate/SKILL.md').read_text()
assert '.guardrail/plan/decomposition.md' in dg_manifest['description']
assert '.codex/guardrail/plan/decomposition.md' not in json.dumps(dg_manifest)
for marker in ('## 問題與目標', '## 已知資訊', '## 缺少的資訊', '【假設】', '## 做法與驗證', '## 允許修改範圍'):
    assert marker in dg_skill, marker
assert 'This mode has no human approval step' in dg_skill
loader_skill = (root/'codex/plugins/ai-guardrail-loader/skills/ai-guardrail-loader/SKILL.md').read_text()
for marker in ('.guardrail/plan/decomposition.md', '## 已知資訊', '## 缺少的資訊', '【假設】', '## 允許修改範圍'):
    assert marker in loader_skill, marker
assert 'Decomposition-gate has no human approval step' in loader_skill
for path in (
    root/'codex/plugins/ai-guardrail-loader/skills/ai-guardrail-loader/SKILL.md',
    root/'codex/plugins/harness/skills/harness/SKILL.md',
    root/'codex/plugins/integrated-harness/skills/integrated-harness/SKILL.md',
):
    text=path.read_text()
    assert 'complete' in text and 'copy-ready' in text and 'placeholder' in text, path
print('PASS: Codex marketplace, loader and runtime manifest structure')
PY
