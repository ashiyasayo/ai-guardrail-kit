#!/usr/bin/env bash
set -euo pipefail
export PYTHONUTF8=1
root=$(cd "$(dirname "$0")/.." && pwd -P)
ROOT="$root" python3 - <<'PY'
import concurrent.futures, importlib.util, json, os, subprocess, sys, tempfile, time
from pathlib import Path
root = Path(os.environ['ROOT'])
sys.path.insert(0, str(root/'shared/codex'))
import approval

def event(project, command='touch example.txt'):
    return {'cwd':str(project), 'hook_event_name':'PreToolUse', 'model':'test',
            'permission_mode':'default','session_id':'s','tool_name':'Bash',
            'tool_input':{'command':command}, 'tool_use_id':'u','transcript_path':None,'turn_id':'t'}

def run(data, mode='harness'):
    result = subprocess.run([sys.executable, str(root/'codex/plugins'/mode/'hooks/plan_gate.py')],
                            input=json.dumps(data), text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)['hookSpecificOutput'] if result.stdout.strip() else None

def deny(data, mode='harness'):
    result = run(data, mode)
    assert result and result['permissionDecision']=='deny', result
    return result

with tempfile.TemporaryDirectory() as tmp:
    base=Path(tmp).resolve(); project=base/'project'; project.mkdir()
    os.environ['CODEX_HOME']=str(base/'home/.codex')
    data=event(project)
    mode='harness'
    digest, _=approval.operation(data, project, mode)
    assert digest in deny(data)['permissionDecisionReason']
    descriptive=event(project); descriptive['tool_input']['description']='review text'
    assert approval.operation(descriptive, project, mode)[0]==digest
    approval.grant(data, project, mode, digest)
    deny(event(project, 'touch different.txt'))
    assert run(data) is None
    deny(data)
    # 兩個程序競爭同一張憑證，最多只放行一次。
    approval.grant(data, project, mode, digest)
    with concurrent.futures.ThreadPoolExecutor(2) as executor:
        results=list(executor.map(lambda _:run(data), range(2)))
    assert results.count(None)==1, results
    receipt=approval.approval_directory(project)/(digest+'.json')
    for changes in ({'expires_at':time.time()-1}, {'issued_at':time.time()+3600}, {'expires_at':time.time()+3600}, {'digest':'0'*64}):
        approval.grant(data, project, mode, digest)
        record=json.loads(receipt.read_text());record.update(changes);receipt.write_text(json.dumps(record))
        deny(data)
    receipt.unlink()
    outside=base/'outside';outside.write_text('{}');receipt.symlink_to(outside)
    deny(data)
    assert outside.read_text()=='{}'
    receipt.unlink()
    # 相同命令不得跨專案、cwd 或模式使用。
    approval.grant(data, project, mode, digest)
    other=base/'other';other.mkdir();deny(event(other))
    sub=project/'sub';sub.mkdir();deny(event(sub))
    # integrated 的內容與政策都必須與人類審閱版本一致。
    plan=project/'.guardrail/plan/decomposition.md';plan.parent.mkdir(parents=True)
    plan.write_text('## 已知資訊\n## 缺少的資訊\n【假設】x\n## 允許修改範圍\n- `src/`\n')
    policy=project/'.codex/guardrail/orchestration-policy.md';policy.parent.mkdir(parents=True)
    policy.write_text('- Approval Mode: standard\n')
    integrated_digest,_=approval.operation(data,project,'integrated-harness')
    approval.grant(data,project,'integrated-harness',integrated_digest)
    plan.write_text(plan.read_text()+'changed\n')
    deny(data,'integrated-harness')
    integrated_digest,_=approval.operation(data,project,'integrated-harness')
    approval.grant(data,project,'integrated-harness',integrated_digest)
    policy.write_text(policy.read_text()+'changed\n')
    deny(data,'integrated-harness')
    integrated_digest,_=approval.operation(data,project,'integrated-harness')
    approval.grant(data,project,'integrated-harness',integrated_digest)
    assert run(data,'integrated-harness') is None
    deny(data,'integrated-harness')
    # preview 不建立憑證；錯誤的確認 digest 也不得授權。
    cli=[sys.executable,str(root/'shared/codex/approval.py'),'--project',str(project),'--mode','harness','--command','touch reviewed.txt']
    preview=subprocess.run(cli,text=True,capture_output=True);assert preview.returncode==0,preview.stderr
    confirm=preview.stdout.strip().split()[-1]
    denied_event=event(project,'touch reviewed.txt');deny(denied_event)
    assert subprocess.run(cli+['--confirm','0'*64],capture_output=True).returncode==1
    assert subprocess.run(cli+['--confirm',confirm],capture_output=True).returncode==0
    assert run(denied_event) is None
    # light 不能經可寫草稿擴大免核准範圍。
    policy.write_text('- Approval Mode: light\n')
    patch=event(project);patch['tool_name']='apply_patch'
    patch['tool_input']={'command':'*** Begin Patch\n*** Update File: .guardrail/plan/decomposition.md\n@@\n+x\n*** End Patch'}
    assert '人類終端機' in deny(patch,'integrated-harness')['permissionDecisionReason']
print('PASS: Codex operation approvals, expiry, binding, replay and concurrency')
PY
