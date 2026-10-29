#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json
import pathlib
import re

root = pathlib.Path('.')
manifest = json.loads((root / 'codex/runtime-manifest.json').read_text(encoding='utf-8'))
assert manifest['schema_version'] == 2
assert 'commit' not in manifest['release']
for mode, item in manifest['modes'].items():
    assert item['archive_path'] == f'codex/runtime-archives/codex-runtime-{mode}.tar.gz'
    assert 'archive_url' not in item

workflow = (root / '.github/workflows/release.yml').read_text(encoding='utf-8')
for required in (
    'environment: release',
    'AGK_TEST_PROFILE: full',
    'git rev-parse "${tag}^{commit}"',
    'git merge-base --is-ancestor "$commit" origin/main',
    'release-commit-sha.txt',
    'gh release create "$GITHUB_REF_NAME"',
    '--verify-tag',
):
    assert required in workflow, required
assert re.search(r'\[0-9a-f\]\{40\}', workflow)

versioning = (root / 'VERSIONING.md').read_text(encoding='utf-8')
assert 'release-commit-sha.txt' in versioning
assert 'GitHub Environment `release`' in versioning
print('PASS: release workflow publishes an external 40-hex runtime trust anchor')
PY
