#!/usr/bin/env bash
set -euo pipefail
export PYTHONUTF8=${PYTHONUTF8:-1}
root=$(cd "$(dirname "$0")/.." && pwd -P)
ROOT="$root" python3 - <<'PY'
import hashlib, importlib.util, io, json, os, shutil, sys, tarfile, tempfile, time
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

# AGK-003: manifest 必須與其實際被要求的 commit 一致，archive URL 必須以路徑
# 區段方式綁定到該 commit；兩者都只落在 approved host 上並不足夠。
_commit_a = 'a' * 40
_commit_b = 'b' * 40


def _manifest_bytes(commit, archive_url):
    payload = {
        'schema_version': 1,
        'release': {
            'source': 'https://github.com/ashiyasayo/ai-guardrail-kit',
            'ref': commit, 'commit': commit, 'runtime_version': 'test+' + commit[:8],
        },
        'modes': {
            mode: {
                'archive_url': archive_url,
                'archive_sha256': digest, 'archive_size': len(archive),
                'entrypoints': {
                    'decomposition-gate': {'pretool.decomposition': 'hooks/dispatch.py'},
                    'sensitive-data-guard': {'pretool.security': 'hooks/dispatch.py', 'pretool.pii': 'hooks/dispatch.py', 'prompt.pii': 'hooks/dispatch.py'},
                    'harness': {'pretool.plan': 'hooks/dispatch.py', 'pretool.security': 'hooks/dispatch.py', 'pretool.pii': 'hooks/dispatch.py', 'prompt.pii': 'hooks/dispatch.py'},
                    'integrated-harness': {'pretool.plan': 'hooks/dispatch.py', 'pretool.security': 'hooks/dispatch.py', 'pretool.pii': 'hooks/dispatch.py', 'prompt.pii': 'hooks/dispatch.py', 'session.start': 'hooks/dispatch.py'},
                }[mode],
            }
            for mode in m.MODES
        },
    }
    return json.dumps(payload).encode()


_pinned_url = 'https://github.com/ashiyasayo/ai-guardrail-kit/releases/download/' + _commit_a + '/x.tar.gz'
_mutable_url = 'https://github.com/ashiyasayo/ai-guardrail-kit/releases/download/main/x.tar.gz'

m.validate_manifest(_manifest_bytes(_commit_a, _pinned_url), expected_ref=_commit_a)

try:
    m.validate_manifest(_manifest_bytes(_commit_b, _pinned_url), expected_ref=_commit_a)
except m.ManagerError as e:
    assert e.code == 'E_MANIFEST_INVALID'
else:
    raise AssertionError('manifest commit mismatched with the immutable fetch ref was accepted')

try:
    m.validate_manifest(_manifest_bytes(_commit_a, _mutable_url), expected_ref=_commit_a)
except m.ManagerError as e:
    assert e.code == 'E_MANIFEST_INVALID'
else:
    raise AssertionError('archive URL not pinned to the manifest commit was accepted')

with tempfile.TemporaryDirectory() as td:
    manifest_path = Path(td) / 'manifest.json'
    manifest_path.write_bytes(_manifest_bytes(_commit_a, _pinned_url))
    old_codex_home = os.environ.get('CODEX_HOME')
    os.environ['CODEX_HOME'] = str(Path(td) / '.codex-home')
    os.environ.pop('AI_GUARDRAIL_ALLOW_DEVELOPMENT_SOURCE', None)
    os.environ.pop('AI_GUARDRAIL_MANIFEST_PATH', None)
    os.environ.pop('AI_GUARDRAIL_ARCHIVE_DIR', None)
    os.environ.pop('AI_GUARDRAIL_ALLOW_MUTABLE_REF', None)
    try:
        import argparse
        args = argparse.Namespace(project=td, scope='project', mode='harness', ref=None,
                                   source=None, update=False, offline=False, owner=None)
        try:
            m.prepare_selection(args)
        except m.ManagerError as e:
            assert e.code == 'E_USAGE'
        else:
            raise AssertionError('fresh github install without --ref silently trusted the mutable main branch')
    finally:
        if old_codex_home is None:
            os.environ.pop('CODEX_HOME', None)
        else:
            os.environ['CODEX_HOME'] = old_codex_home

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

    # 執行 hook 時 CPython 匯入同目錄模組會在 payload 留下 __pycache__/*.pyc；
    # 這是執行期自然產生的衍生檔，verify_cache 不應把它當成竄改而拒絕。
    pycache_dir = payload / 'hooks' / '__pycache__'
    pycache_dir.mkdir(parents=True)
    (pycache_dir / 'dispatch.cpython-313.pyc').write_bytes(b'not-a-real-pyc')
    (payload / 'hooks' / 'dispatch.cpython-313.pyo').write_bytes(b'not-a-real-pyo')
    assert store.verify_cache(identity) == payload, \
        'stray __pycache__/.pyc/.pyo must not fail runtime cache verification'
    shutil.rmtree(pycache_dir)
    (payload / 'hooks' / 'dispatch.cpython-313.pyo').unlink()

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
    assert captured['environment']['PYTHONDONTWRITEBYTECODE'] == '1'
    assert captured['environment']['AI_GUARDRAIL_MODE'] == 'harness'
    assert 'AI_GUARDRAIL_MANIFEST_PATH' not in captured['environment']
    assert 'SHOULD_NOT_LEAK_TOKEN' not in captured['environment']

# AGK-004: 未登錄於受保護 registry 的 project/local selector，即使指向已快取
# 且完整合法的 runtime，也不得被 resolve_runtime 採用（避免未受信任專案降級
# 使用者原本期待的防護模式）。
with tempfile.TemporaryDirectory() as td:
    store = m.RuntimeStore(Path(td) / '.codex')
    store.install(identity, archive)
    project = Path(td) / 'project'
    selector = project / '.codex/guardrail/runtime.json'
    selector.parent.mkdir(parents=True)
    event = {'cwd': str(project)}

    # 未登錄：直接寫入 selector 檔案，不呼叫 register_selector（模擬攻擊者
    # 提交版本控制的 project selector）。
    m._atomic_write(selector, m._json_bytes(
        {'schema_version': 1, 'scope': 'project', 'mode': 'harness', 'identity': identity}))
    resolved_identity, resolved_payload, _ = m.resolve_runtime(event, store)
    assert resolved_identity is None and resolved_payload is None, \
        'unregistered project selector must not be trusted'

    # 登錄後，同一份 selector 才應被信任並解析成功。
    m.register_selector(store, selector, 'project', identity)
    resolved_identity, resolved_payload, _ = m.resolve_runtime(event, store)
    assert resolved_identity == identity and resolved_payload is not None, \
        'registered project selector must resolve normally'

# fail-closed 輸出形狀必須與觸發它的事件相符：UserPromptSubmit 用
# {"continue": false, "stopReason", "systemMessage"}，不能沿用 PreToolUse 專用
# 的 hookSpecificOutput.permissionDecision（否則 Codex 會回報 "hook returned
# invalid user prompt submit JSON output"，掩蓋原本的 E_CACHE_CORRUPT 根因）。
for event_name, checker in (
    ('SessionStart', lambda o: o['hookSpecificOutput']['hookEventName'] == 'SessionStart' and 'additionalContext' in o['hookSpecificOutput']),
    ('UserPromptSubmit', lambda o: o.get('continue') is False and isinstance(o.get('stopReason'), str) and isinstance(o.get('systemMessage'), str)),
    ('PreToolUse', lambda o: o['hookSpecificOutput']['hookEventName'] == 'PreToolUse' and o['hookSpecificOutput']['permissionDecision'] == 'deny'),
):
    output = json.loads(m._failure_output(event_name, 'E_CACHE_CORRUPT'))
    assert checker(output), (event_name, output)

# loader.py 的更早期 fail-closed 路徑（manager.py 尚無法載入時）必須遵循同樣的
# 事件對應輸出形狀；loader.py 沒有獨立的 scripts/ 副本，不受逐位元組同步測試
# 約束，需要單獨載入驗證。
loader_spec = importlib.util.spec_from_file_location(
    'ai_guardrail_loader', Path(os.environ['ROOT']) / 'codex/plugins/ai-guardrail-loader/hooks/loader.py')
loader_module = importlib.util.module_from_spec(loader_spec)
loader_spec.loader.exec_module(loader_module)


def _run_fail_closed(event_name):
    captured = io.BytesIO()
    old_stdout = sys.stdout
    sys.stdout = type('X', (), {'buffer': captured})()
    try:
        loader_module._fail_closed(json.dumps({'hook_event_name': event_name}).encode())
    finally:
        sys.stdout = old_stdout
    return json.loads(captured.getvalue())


assert _run_fail_closed('SessionStart')['hookSpecificOutput']['additionalContext']
prompt_output = _run_fail_closed('UserPromptSubmit')
assert prompt_output.get('continue') is False and isinstance(prompt_output.get('stopReason'), str) and isinstance(prompt_output.get('systemMessage'), str)
pretool_output = _run_fail_closed('PreToolUse')
assert pretool_output['hookSpecificOutput']['permissionDecision'] == 'deny'
print('PASS: Codex runtime manager archive and payload integrity')
PY
