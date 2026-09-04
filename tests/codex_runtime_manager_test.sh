#!/usr/bin/env bash
set -euo pipefail
export PYTHONUTF8=${PYTHONUTF8:-1}
root=$(cd "$(dirname "$0")/.." && pwd -P)
ROOT="$root" python3 - <<'PY'
import hashlib, importlib.util, io, json, os, sys, tarfile, tempfile, time
from pathlib import Path
import os
spec=importlib.util.spec_from_file_location('manager', Path(os.environ['ROOT'])/'scripts/codex-runtime-manager.py')
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def bundle(member='hooks/dispatch.py', kind='regular', data=b'print("ok")\n'):
    out=io.BytesIO()
    with tarfile.open(fileobj=out, mode='w:gz') as t:
        if kind == 'symlink':
            info=tarfile.TarInfo(member); info.type=tarfile.SYMTYPE; info.linkname='outside'; t.addfile(info)
        elif kind == 'hardlink':
            info=tarfile.TarInfo('hooks/base.py'); info.size=1; t.addfile(info, io.BytesIO(b'x'))
            info=tarfile.TarInfo(member); info.type=tarfile.LNKTYPE; info.linkname='hooks/base.py'; t.addfile(info)
        else:
            info=tarfile.TarInfo(member); info.size=len(data); t.addfile(info, io.BytesIO(data))
    return out.getvalue()

for kind in ('symlink','hardlink'):
    try: m.extract_verified_archive(bundle(kind=kind), Path(tempfile.mkdtemp())/'payload', {'x':'hooks/dispatch.py'})
    except m.ManagerError as e: assert e.code == 'E_ARCHIVE_UNSAFE'
    else: raise AssertionError(kind + ' accepted')

archive=bundle(); digest=hashlib.sha256(archive).hexdigest()
identity={'schema_version':1,'mode':'harness','source':'test','ref':'test','commit':'1'*40,'runtime_version':'test+1','archive_url':'https://github.com/ashiyasayo/ai-guardrail-kit/releases/download/test/x.tar.gz','archive_sha256':digest,'archive_size':len(archive),'entrypoints':{'pretool.plan':'hooks/dispatch.py','pretool.security':'hooks/dispatch.py','pretool.pii':'hooks/dispatch.py','prompt.pii':'hooks/dispatch.py'}}

loader=Path('C:/guardrail/loader/loader.py')
assert m._loader_hook_command('C:/Program Files/Python/python.exe', loader, 'session.start', True) == (
    "$env:AI_GUARDRAIL_LOADER_SLOT = 'session.start'; $env:AI_GUARDRAIL_LOADER = '1'; "
    "& 'C:/Program Files/Python/python.exe' -- 'C:/guardrail/loader/loader.py'")
assert m._is_loader_command(
    "$env:AI_GUARDRAIL_LOADER_SLOT = 'session.start'; $env:AI_GUARDRAIL_LOADER = '1'; "
    "& 'C:/Program Files/Python/python.exe' -- 'C:/guardrail/loader/loader.py'")
assert m._loader_hook_command('/usr/bin/python3', Path('/guardrail/loader/loader.py'), 'session.start', False) == (
    'AI_GUARDRAIL_LOADER_SLOT=session.start AI_GUARDRAIL_LOADER=1 '
    '/usr/bin/python3 -- /guardrail/loader/loader.py')

with tempfile.TemporaryDirectory() as td:
    store=m.RuntimeStore(Path(td)/'.codex'); store.install(identity, archive)
    payload=store.cache_path(digest)/'payload'; (payload/'hooks/dispatch.py').write_bytes(b'tampered')
    try: store.verify_cache(identity)
    except m.ManagerError as e: assert e.code == 'E_CACHE_CORRUPT'
    else: raise AssertionError('tampered payload accepted')
    store.install(identity, archive)
    assert (payload/'hooks/dispatch.py').read_bytes() == b'print("ok")\n'

    archive2=bundle(data=b'print("unreferenced")\n'); digest2=hashlib.sha256(archive2).hexdigest()
    identity2=dict(identity); identity2.update({'archive_sha256':digest2, 'archive_size':len(archive2), 'commit':'2'*40, 'runtime_version':'test+2'})
    store.install(identity2, archive2)
    project=Path(td)/'project'; selector=project/'.codex/guardrail/runtime.json'; selector.parent.mkdir(parents=True)
    m._atomic_write(selector, m._json_bytes({'schema_version':1, 'scope':'project', 'mode':'harness', 'identity':identity}))
    m.register_selector(store, selector, 'project', identity)
    old=time.time()-90*86400
    os.utime(store.cache_path(digest2), (old, old))
    preview=m.prune_cache(store, 30, dry_run=True)
    assert digest2 in preview and store.cache_path(digest2).exists()
    removed=m.prune_cache(store, 30, dry_run=False)
    assert digest2 in removed and not store.cache_path(digest2).exists()
    assert store.cache_path(digest).exists()

    captured={}
    class RecordingProcess(m.HookProcess):
        def run(self, python, entrypoint, event, environment):
            captured.update({'python':python, 'entrypoint':entrypoint, 'event':event, 'environment':environment})
            return 0, b'', b''
    old_slot=os.environ.get('AI_GUARDRAIL_LOADER_SLOT')
    os.environ['AI_GUARDRAIL_LOADER_SLOT']='pretool.security'
    os.environ['AI_GUARDRAIL_PYTHON']='should-not-be-used'
    os.environ['AI_GUARDRAIL_MANIFEST_PATH']='should-not-leak'
    os.environ['SHOULD_NOT_LEAK_TOKEN']='secret'
    try:
        assert m.dispatch(json.dumps({'cwd':str(project), 'hook_event_name':'PreToolUse'}).encode(), store, RecordingProcess()) == 0
    finally:
        if old_slot is None: os.environ.pop('AI_GUARDRAIL_LOADER_SLOT', None)
        else: os.environ['AI_GUARDRAIL_LOADER_SLOT']=old_slot
        os.environ.pop('AI_GUARDRAIL_PYTHON', None)
        os.environ.pop('AI_GUARDRAIL_MANIFEST_PATH', None)
        os.environ.pop('SHOULD_NOT_LEAK_TOKEN', None)
    assert captured['python'] == sys.executable
    assert captured['environment']['AI_GUARDRAIL_MODE'] == 'harness'
    assert 'AI_GUARDRAIL_MANIFEST_PATH' not in captured['environment']
    assert 'SHOULD_NOT_LEAK_TOKEN' not in captured['environment']
print('PASS: Codex runtime manager archive and payload integrity')
PY
