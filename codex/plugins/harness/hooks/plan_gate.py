#!/usr/bin/env python3
import hashlib,json,re,shlex,sys,time
from hook_protocol import deny,load_event,project_root
PLAN=".codex/guardrail/plan/decomposition.md"; APPROVAL=".codex/guardrail/approval.json"; TTL=3600
UNSAFE=re.compile(r"[;&|><`\n\r]|\$\(|\btee\b|\bxargs\b")
READ={"ls","cat","head","tail","grep","rg","pwd","which","file","wc","diff","stat"}
def readonly(c):
 try:t=shlex.split(c)
 except ValueError:return False
 return bool(t) and not UNSAFE.search(c) and (t[0] in READ or (len(t)>1 and t[0]=="git" and t[1] in {"status","log","diff","show","branch"}))
def valid(root):
 try:r=json.loads((root/APPROVAL).read_text()); ts=r["approved_at"]; digest=r["plan_sha256"]
 except (OSError,ValueError,TypeError,KeyError):return False
 now=time.time()
 return isinstance(ts,(int,float)) and isinstance(digest,str) and re.fullmatch(r"[0-9a-f]{64}",digest) is not None and ts<=now+60 and now-ts<=TTL and digest==hashlib.sha256((root/PLAN).read_bytes()).hexdigest()
def main():
 e=load_event(sys.stdin); root=project_root(e); i=e["tool_input"]
 target=i.get("file_path") or i.get("notebook_path") or ""
 if target and (root/target).resolve()==(root/APPROVAL).resolve():deny("核准紀錄只能由人類操作。")
 if e["tool_name"]=="Bash":
  c=i.get("command","")
  if "approval.json" in c:deny("核准紀錄只能由人類操作。")
  if readonly(c):return
 if not valid(root):deny("計畫閘門：沒有目前且有效的人類核准。")
if __name__=="__main__":main()
