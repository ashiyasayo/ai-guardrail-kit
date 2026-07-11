#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, pathlib, sys

def check(condition, message):
 if not condition:
  print(f'FAIL: {message}', file=sys.stderr)
  raise SystemExit(1)

root=pathlib.Path('.')
data=json.loads((root/'codex/marketplace.json').read_text())
names=['decomposition-gate','harness','integrated-harness']
check(data.get('name')=='ai-guardrail-kit', 'marketplace name must be ai-guardrail-kit')
check([p.get('name') for p in data.get('plugins', [])]==names, f'plugin order must be {names}')
for p,name in zip(data['plugins'],names):
 check(p.get('source')=={'source':'local','path':f'./plugins/{name}'}, f'{name}: invalid local source')
 check(p.get('policy')=={'installation':'AVAILABLE','authentication':'ON_INSTALL'}, f'{name}: invalid policy')
 check(p.get('category')=='Security', f'{name}: category must be Security')
 base=root/'codex'/p['source']['path'].removeprefix('./')
 manifest=json.loads((base/'.codex-plugin/plugin.json').read_text())
 check(base.name==manifest.get('name')==name, f'{name}: directory and manifest names must match')
 check(manifest.get('version')=='0.1.0', f'{name}: version must be 0.1.0')
 skills=list(base.glob('skills/*/SKILL.md'))
 check(len(skills)==1, f'{name}: expected exactly one skill, found {len(skills)}')
 text=skills[0].read_text()
 lines=text.splitlines()
 check(lines and lines[0].strip()=='---', f'{name}: SKILL.md must begin with YAML frontmatter')
 try:
  closing=next(i for i,line in enumerate(lines[1:], 1) if line.strip()=='---')
 except StopIteration:
  check(False, f'{name}: SKILL.md frontmatter is missing closing ---')
 frontmatter=lines[1:closing]
 frontmatter_names=[line.split(':',1)[1].strip() for line in frontmatter if line.startswith('name:')]
 check(frontmatter_names==[name], f'{name}: frontmatter name must be {name}, found {frontmatter_names}')
print('PASS: Codex marketplace and plugin skeletons')
PY
