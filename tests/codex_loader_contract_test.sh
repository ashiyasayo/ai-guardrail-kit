#!/usr/bin/env bash
set -euo pipefail
export PYTHONUTF8=1
root=$(cd "$(dirname "$0")/.." && pwd -P)
ROOT="$root" python3 - <<'PY'
import importlib.util,json,os,re,subprocess,sys,tempfile
from pathlib import Path
root=Path(os.environ['ROOT'])
runtime_ref=json.loads((root/'codex/runtime-manifest.json').read_text())['release']['ref']
spec=importlib.util.spec_from_file_location('manager',root/'scripts/codex-runtime-manager.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as tmp:
    base=Path(tmp).resolve();project=base/'project';project.mkdir()
    os.environ.update(CODEX_HOME=str(base/'home/.codex'),AI_GUARDRAIL_ALLOW_DEVELOPMENT_SOURCE='1',AI_GUARDRAIL_MANIFEST_PATH=str(root/'codex/runtime-manifest.json'),AI_GUARDRAIL_ARCHIVE_DIR=str(root/'codex/runtime-archives'))
    store=m.RuntimeStore(m.codex_home())
    # 使用真實 archive、selector registry 與 loader 子程序，不以假的 hook 回傳取代。
    loader=store.root/'loader';loader.mkdir(parents=True)
    for name,source in [('loader.py',root/'codex/plugins/ai-guardrail-loader/hooks/loader.py'),('manager.py',root/'scripts/codex-runtime-manager.py')]:
        (loader/name).write_bytes(source.read_bytes())
    (loader/'current.json').write_text(json.dumps({'schema_version':1,'complete':True}))
    hooks=m._loader_hook_data(store.root.parent/'hooks.json',sys.executable,'install')
    (store.root.parent/'hooks.json').write_text(json.dumps(hooks))
    def invoke(slot,event):
        result=subprocess.run([sys.executable,str(loader/'loader.py')],input=json.dumps(event),text=True,capture_output=True,env=dict(os.environ,AI_GUARDRAIL_LOADER_SLOT=slot))
        assert result.returncode==0,result.stderr
        return json.loads(result.stdout) if result.stdout.strip() else None
    event={'cwd':str(project),'hook_event_name':'PreToolUse','model':'test','permission_mode':'default','session_id':'s','tool_name':'Bash','tool_input':{'command':'git reset --hard'},'tool_use_id':'u','transcript_path':None,'turn_id':'t'}
    for mode in m.MODES:
        args=m.parser().parse_args(['select',mode,'--project',str(project),'--source','local','--ref',runtime_ref])
        prepared=m.prepare_selection(args);m.commit_selection(prepared,'project',store)
        diagnose=m.parser().parse_args(['verify',mode,'--project',str(project),'--diagnose'])
        m.diagnose_selection(diagnose)
        slots=[]
        for rule in hooks['hooks']['PreToolUse']:
            if re.search(rule['matcher'],'Bash'):
                command=rule['hooks'][0]['command']
                slots.extend(slot for slot in m.SLOTS if slot in command)
        assert {'pretool.decomposition','pretool.plan','pretool.security'} <= set(slots)
        if mode in ('harness','integrated-harness'):
            result=invoke('pretool.security',event)
            assert '危險指令攔截' in result['hookSpecificOutput']['permissionDecisionReason'],result
        if mode=='harness':
            command='touch approved-canary'
            cli=[sys.executable,str(root/'scripts/codex-runtime-manager.py'),'approve','--project',str(project),'--command',command]
            preview=subprocess.run(cli,text=True,capture_output=True)
            assert preview.returncode==0,preview.stderr
            digest=preview.stdout.strip().split()[-1]
            candidate=dict(event,tool_input={'command':command})
            assert invoke('pretool.plan',candidate)['hookSpecificOutput']['permissionDecision']=='deny'
            confirmed=subprocess.run(cli+['--confirm',digest],text=True,capture_output=True)
            assert confirmed.returncode==0,confirmed.stderr
            assert invoke('pretool.plan',candidate) is None
            assert invoke('pretool.plan',candidate)['hookSpecificOutput']['permissionDecision']=='deny'
        if mode!='decomposition-gate':
            patch=dict(event,tool_name='apply_patch',tool_input={'command':'*** Begin Patch\n*** Add File: x\n+test@example.com\n*** End Patch'})
            result=invoke('pretool.pii',patch)['hookSpecificOutput']
            assert result['permissionDecision']=='allow'
            assert 'test@example.com' not in result['updatedInput']['command']
        if mode=='decomposition-gate':
            patch=dict(event,tool_name='apply_patch',tool_input={'command':'*** Begin Patch\n*** Add File: .guardrail/plan/decomposition.md\n+draft\n*** End Patch'})
            assert invoke('pretool.decomposition',patch) is None
    # 舊 matcher 不得被診斷為可用。
    hooks['hooks']['PreToolUse'][0]['matcher']='exec_command|apply_patch'
    (store.root.parent/'hooks.json').write_text(json.dumps(hooks))
    try:m.diagnose_selection(diagnose)
    except m.ManagerError as error:assert error.code=='E_HOOK_WIRING'
    else:raise AssertionError('outdated matcher accepted')
print('PASS: Codex real archive/loader contract and wiring diagnostics')
PY
