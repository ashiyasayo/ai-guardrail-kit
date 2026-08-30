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
    assert policy == ('AVAILABLE' if name=='ai-guardrail-loader' else 'DEPRECATED')
    manifest=json.loads((base/'.codex-plugin/plugin.json').read_text())
    assert manifest['name']==name
    skills=list((base/'skills').glob('*/SKILL.md'))
    assert len(skills)==1
    assert ('new thread' in skills[0].read_text()) if name != 'ai-guardrail-loader' else True
loader=root/'codex/plugins/ai-guardrail-loader/hooks'
for name in ('loader.py','manager.py','select-codex-mode','verify-codex-mode','install-codex-guardrail-loader','prune-codex-runtime-cache'):
    assert (loader/name).is_file(), name
manifest=json.loads((root/'codex/runtime-manifest.json').read_text())
assert manifest['schema_version']==1 and set(manifest['modes'])==set(names[1:])
for item in manifest['modes'].values():
    assert re.fullmatch(r'[0-9a-f]{64}', item['archive_sha256'])
    assert item['archive_size'] > 0
    archive=root/'codex/runtime-archives'/pathlib.PurePosixPath(item['archive_url']).name
    assert archive.is_file() and archive.stat().st_size == item['archive_size']
    assert __import__('hashlib').sha256(archive.read_bytes()).hexdigest() == item['archive_sha256']
guide=(root/'docs/codex-marketplace.md').read_text()
for needle in ('ai-guardrail-loader@ai-guardrail-kit','runtime.local.json','--offline','E_ARCHIVE_UNSAFE','shell=False','no-checkout','selector-index.json','--apply'):
    assert needle in guide, needle
readme=(root/'README.md').read_text()
assert 'hook 熱路徑' in readme and 'ai-guardrail-loader' in readme
print('PASS: Codex marketplace, loader and runtime manifest structure')
PY
