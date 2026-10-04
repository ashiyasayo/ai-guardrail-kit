#!/usr/bin/env bash
set -euo pipefail
# 明確啟用才啟動真實 CLI；模型回應由 loopback fixture 提供，不使用帳號或額度。
if [[ ${AGK_CODEX_HOST_TEST:-0} != 1 && ${1:-} != --run ]]; then
  printf 'SKIP: actual Codex host test (set AGK_CODEX_HOST_TEST=1; requires CLI and loopback listener)\n'
  exit 0
fi
export PYTHONUTF8=1
root=$(cd "$(dirname "$0")/.." && pwd -P)
ROOT="$root" python3 - <<'PY'
import importlib.util,json,os,shlex,shutil,subprocess,sys,tempfile,threading
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
root=Path(os.environ['ROOT']);codex=shutil.which('codex')
assert codex,'Codex CLI is required'
spec=importlib.util.spec_from_file_location('manager',root/'scripts/codex-runtime-manager.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory(prefix='agk-host-') as tmp:
    base=Path(tmp).resolve();project=base/'project';project.mkdir()
    home=base/'codex-home';home.mkdir()
    env=dict({key:os.environ[key] for key in ('PATH','SystemRoot','WINDIR','TEMP','TMP','TMPDIR') if key in os.environ},HOME=str(base/'human-home'),USERPROFILE=str(base/'human-home'),PYTHONUTF8='1',CODEX_HOME=str(home),AI_GUARDRAIL_ALLOW_DEVELOPMENT_SOURCE='1',AI_GUARDRAIL_MANIFEST_PATH=str(root/'codex/runtime-manifest.json'),AI_GUARDRAIL_ARCHIVE_DIR=str(root/'codex/runtime-archives'))
    os.environ.update(env)
    store=m.RuntimeStore(home)
    args=m.parser().parse_args(['select','harness','--scope','user','--project',str(project),'--source','local','--ref','main'])
    prepared=m.prepare_selection(args);m.commit_selection(prepared,'user',store)
    loader=store.root/'loader';loader.mkdir(parents=True)
    for name,source in [('loader.py',root/'codex/plugins/ai-guardrail-loader/hooks/loader.py'),('manager.py',root/'scripts/codex-runtime-manager.py')]:
        (loader/name).write_bytes(source.read_bytes())
    # 僅記錄本機 fixture 產生的固定測試輸入；不接收真實使用者 prompt 或命令。
    observer=base/'observe.py';log=base/'observed.jsonl'
    observer.write_text('''import json,os,subprocess,sys
from pathlib import Path
raw=sys.stdin.buffer.read();event=json.loads(raw)
slots=['pretool.pii'] if event.get('tool_name')=='apply_patch' else ['pretool.security','pretool.plan']
for slot in slots:
 r=subprocess.run([sys.executable,sys.argv[1]],input=raw,capture_output=True,env=dict(os.environ,AI_GUARDRAIL_LOADER_SLOT=slot))
 if r.stdout or r.returncode: break
with Path(sys.argv[2]).open('a') as f:
 f.write(json.dumps({'tool':event.get('tool_name'),'input':event.get('tool_input'),'output':json.loads(r.stdout) if r.stdout else None})+'\\n')
sys.stdout.buffer.write(r.stdout);sys.exit(r.returncode)
''')
    if os.name=='nt':
        quote=m._powershell_quote
        command='& '+' '.join(quote(str(x)) for x in (sys.executable,observer,loader/'loader.py',log))
    else:
        command=shlex.join([sys.executable,str(observer),str(loader/'loader.py'),str(log)])
    (home/'hooks.json').write_text(json.dumps({'hooks':{'PreToolUse':[{'matcher':'^(Bash|exec_command|apply_patch)$','hooks':[{'type':'command','command':command}]}]}}))
    (home/'config.toml').write_text('[features]\nhooks = true\n')
    class ResponsesFixture(BaseHTTPRequestHandler):
        calls=0
        def log_message(self,*args): pass
        def do_POST(self):
            request=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            ResponsesFixture.calls+=1
            index=ResponsesFixture.calls
            patch='*** Begin Patch\n*** Add File: patch-canary.txt\n+test@example.com\n*** End Patch'
            if index==1:
                item={'id':'fc_1','type':'function_call','call_id':'call_1','name':'exec_command','arguments':json.dumps({'cmd':'python3 -c "open(\'shell-canary\',\'w\').write(\'probe\')"'})}
            elif index==2:
                def flatten(tools):
                    for tool in tools:
                        if 'tools' in tool:
                            yield from flatten(tool['tools'])
                        else:
                            yield tool
                definitions=list(flatten(request['tools']))
                definition=next((tool for tool in definitions if tool.get('name')=='apply_patch'),None)
                if definition is None:
                    print('Missing patch capability in fixture catalog',file=sys.stderr,flush=True)
                    self.send_error(400);return
                if definition['type']=='custom':
                    item={'id':'ct_2','type':'custom_tool_call','call_id':'call_2','name':'apply_patch','input':patch}
                else:
                    field=next(iter(definition['parameters']['properties']))
                    item={'id':'fc_2','type':'function_call','call_id':'call_2','name':'apply_patch','arguments':json.dumps({field:patch})}
            elif index in (3,4,5):
                if index==4:
                    # fixture 的人類端審閱程序位於模型沙箱外；hook 本身不簽發核准。
                    cli=[sys.executable,str(root/'scripts/codex-runtime-manager.py'),'approve','--project',str(project),'--command','printf approved > approved-canary']
                    preview=subprocess.run(cli,text=True,capture_output=True,env=env)
                    assert preview.returncode==0,preview.stderr
                    digest=preview.stdout.strip().split()[-1]
                    confirm=subprocess.run(cli+['--confirm',digest],text=True,capture_output=True,env=env)
                    assert confirm.returncode==0,confirm.stderr
                item={'id':'fc_'+str(index),'type':'function_call','call_id':'call_'+str(index),'name':'exec_command','arguments':json.dumps({'cmd':'printf approved > approved-canary','yield_time_ms':1000})}
            else:
                item={'id':'msg_6' ,'type':'message','role':'assistant','status':'completed','content':[{'type':'output_text','text':'Fixture complete.','annotations':[]}]}
            response={'id':'resp_'+str(index),'object':'response','status':'completed','output':[item]}
            events=[('response.created',{'response':dict(response,status='in_progress',output=[])}),
                    ('response.output_item.added',{'output_index':0,'item':item}),
                    ('response.output_item.done',{'output_index':0,'item':item}),
                    ('response.completed',{'response':response})]
            data=''.join('event: '+name+'\ndata: '+json.dumps(dict(body,type=name))+'\n\n' for name,body in events).encode()
            self.send_response(200);self.send_header('Content-Type','text/event-stream');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    server=ThreadingHTTPServer(('127.0.0.1',0),ResponsesFixture)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    # 固定工具輸出驅動真實 CLI；只略過本測試自行產生的 hook trust，保留沙箱。
    catalog=base/'models.json'
    catalog.write_text(json.dumps({'models':[{
        'slug':'fixture-model','display_name':'Fixture','description':'Local deterministic test',
        'default_reasoning_level':'low','supported_reasoning_levels':[],
        'shell_type':'unified_exec','visibility':'list','supported_in_api':True,'priority':0,
        'base_instructions':'Execute the supplied test tool calls.',
        'supports_reasoning_summaries':False,'default_reasoning_summary':'none',
        'support_verbosity':False,'default_verbosity':None,'apply_patch_tool_type':'freeform',
        'truncation_policy':{'mode':'tokens','limit':10000},'parallel_tool_calls':False,
        'context_window':128000,'effective_context_window_percent':95,
        'experimental_supported_tools':[],'input_modalities':['text']
    }]}))
    config=['-c','model_provider="fixture"','-c','model="fixture-model"','-c','model_catalog_json='+json.dumps(str(catalog)),
            '-c','model_providers.fixture.name="Local test fixture"',
            '-c','model_providers.fixture.base_url="http://127.0.0.1:'+str(server.server_port)+'/v1"',
            '-c','model_providers.fixture.wire_api="responses"',
            '-c','model_providers.fixture.requires_openai_auth=false',
            '-c','sandbox_workspace_write.exclude_tmpdir_env_var=true',
            '-c','sandbox_workspace_write.exclude_slash_tmp=true',
            '--disable','plugins','--disable','remote_plugin','--disable','apps',
            '--enable','skip_host_skill_discovery']
    try:
        result=subprocess.run([codex,'exec','--ephemeral','--skip-git-repo-check','--sandbox','workspace-write','--dangerously-bypass-hook-trust','-C',str(project),*config,'Run the disposable hook fixture.'],env=env,text=True,capture_output=True,timeout=90)
    finally:
        server.shutdown();server.server_close()
    assert result.returncode==0,result.stderr
    assert log.exists(), 'host did not invoke the configured hook: '+result.stderr
    records=[json.loads(line) for line in log.read_text().splitlines()]
    assert any(row['tool']=='Bash' and (row['output'] or {}).get('hookSpecificOutput',{}).get('permissionDecision')=='deny' for row in records),records
    assert not (project/'shell-canary').exists(),'host did not enforce deny'
    assert any(row['tool']=='apply_patch' and (row['output'] or {}).get('hookSpecificOutput',{}).get('permissionDecision')=='allow' for row in records),(records,result.stderr)
    assert (project/'patch-canary.txt').read_text().strip()=='t***@example.com','host did not apply updatedInput.command'
    approvals=[row for row in records if row.get('input',{}).get('command')=='printf approved > approved-canary']
    assert len(approvals)==3,records
    assert set(approvals[0]['input']) <= {'command','description'}, approvals[0]['input']
    assert approvals[0]['output']['hookSpecificOutput']['permissionDecision']=='deny'
    assert approvals[1]['output'] is None,approvals
    assert approvals[2]['output']['hookSpecificOutput']['permissionDecision']=='deny'
    assert (project/'approved-canary').read_text()=='approved'
print('PASS: real Codex host dispatch, deny, PII rewrite, one-use approval and workspace-write sandbox')
PY
