#!/usr/bin/env bash
set -euo pipefail
# Windows（Git Bash）環境通常只有 python 而沒有可用的 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
# Windows 預設編碼為 cp950，強制 Python 使用 UTF-8 避免中文讀寫失敗
export PYTHONUTF8=${PYTHONUTF8:-1}
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, pathlib, re, sys

SEMVER_PATTERN = re.compile(r'^\d+\.\d+\.\d+$')

def check(condition, message):
 if not condition:
  print(f'FAIL: {message}', file=sys.stderr)
  raise SystemExit(1)

root=pathlib.Path('.')
data=json.loads((root/'.agents/plugins/marketplace.json').read_text())
names=['decomposition-gate','harness','integrated-harness']
check(data.get('name')=='ai-guardrail-kit', 'marketplace name must be ai-guardrail-kit')
check([p.get('name') for p in data.get('plugins', [])]==names, f'plugin order must be {names}')
for p,name in zip(data['plugins'],names):
 check(p.get('source')=={'source':'local','path':f'./codex/plugins/{name}'}, f'{name}: invalid local source')
 check(p.get('policy')=={'installation':'AVAILABLE','authentication':'ON_INSTALL'}, f'{name}: invalid policy')
 check(p.get('category')=='Security', f'{name}: category must be Security')
 base=root/p['source']['path'].removeprefix('./')
 manifest=json.loads((base/'.codex-plugin/plugin.json').read_text())
 check(base.name==manifest.get('name')==name, f'{name}: directory and manifest names must match')
 # 版號本身由各 plugin.json 維護、隨每次功能變更調整；此測試只驗證格式，
 # 不寫死特定版號，避免每次版號升級都要同步改測試。
 check(SEMVER_PATTERN.match(manifest.get('version', '')), f"{name}: version must be semver, got {manifest.get('version')!r}")
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

readme=(root/'README.md').read_text()
guide_path=root/'docs/codex-marketplace.md'
check(guide_path.exists(), 'docs/codex-marketplace.md must exist')
guide=guide_path.read_text()
check('docs/codex-marketplace.md' in readme, 'README must link to the Codex marketplace guide')
required = {
 'codex plugin marketplace add "$(pwd)"': 'marketplace add command',
 './scripts/select-codex-mode decomposition-gate .': 'selector command',
 './scripts/install-codex-global-integrated-harness': 'global installer command',
 './scripts/verify-codex-global-integrated-harness': 'global verifier command',
 '~/.codex/hooks.json': 'global hook configuration path',
 './scripts/verify-codex-mode decomposition-gate .': 'verifier command',
 './scripts/select-codex-mode --remove /path/to/project': 'safe remove command',
 './scripts/verify-codex-mode --no-managed-mode /path/to/project': 'removed-state verifier command',
 '.codex/config.toml': 'managed config path',
 '# ai-guardrail-kit:begin': 'managed block delimiter',
 'Python 3.9': 'Python minimum',
 'new thread': 'new-thread activation instruction',
 'native Codex `ask`': 'native approval semantics',
 'codex plugin add/remove': 'direct CLI desynchronization boundary',
 'refresh': 'local update workflow',
 'codex plugin marketplace upgrade ai-guardrail-kit': 'remote marketplace snapshot upgrade',
 './scripts/select-codex-mode --update': 'selector remote update command',
 'update applied but verification failed': 'post-commit refresh failure',
 'irreversible update commit point': 'refresh commit point',
 'TOCTOU': 'selector race limitation',
}
for needle, label in required.items():
 check(needle in guide, f'Codex guide must document {label}')
check('/Users/' not in guide, 'Codex guide must not contain a developer-machine path')
check('removes and re-adds' not in guide, 'Codex guide retains obsolete refresh workaround')
check('refreshes cached plugin content with transactional rollback' not in guide, 'Codex guide falsely promises refresh rollback')
for name in names:
 skill=(root/f'codex/plugins/{name}/skills/{name}/SKILL.md').read_text()
 check('new thread' in skill, f'{name}: skill must require a new thread')
 check(f'scripts/select-codex-mode {name}' in skill, f'{name}: skill must name its selector command')
print('PASS: Codex marketplace and plugin skeletons')
PY
