#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, pathlib, re
root=pathlib.Path('.')
data=json.loads((root/'codex/marketplace.json').read_text())
names=['decomposition-gate','harness','integrated-harness']
assert data['name']=='ai-guardrail-kit'
assert [p['name'] for p in data['plugins']]==names
for p,name in zip(data['plugins'],names):
 assert p['source']=={'source':'local','path':f'./plugins/{name}'}
 assert p['policy']=={'installation':'AVAILABLE','authentication':'ON_INSTALL'}
 assert p['category']=='Security'
 base=root/'codex'/p['source']['path'].removeprefix('./')
 manifest=json.loads((base/'.codex-plugin/plugin.json').read_text())
 assert base.name==manifest['name']==name
 assert manifest['version']=='0.1.0'
 skills=list(base.glob('skills/*/SKILL.md'))
 assert len(skills)==1
 text=skills[0].read_text()
 assert re.search(r'^name:\s*'+re.escape(name)+r'\s*$',text,re.M)
print('PASS: Codex marketplace and plugin skeletons')
PY
