#!/usr/bin/env python3
import hashlib,json,re,shlex,sys,time
from hook_protocol import deny,load_event,project_root
PLAN=".codex/guardrail/plan/decomposition.md";APP=".codex/guardrail/approval.json";POL=".codex/guardrail/orchestration-policy.md"
MARKERS=("## 已知資訊","## 缺少的資訊","【假設】"); PATHS={"Write":"file_path","Edit":"file_path","MultiEdit":"file_path","NotebookEdit":"notebook_path"}
MODE=re.compile(r"(?m)^\s*-\s+核准模式[：:]\s*(strict|standard|light)\s*$"); UNSAFE=re.compile(r"[;&|><`\n\r*?\[\]]|\$\(")
def mode(root):
 try:m=MODE.search((root/POL).read_text())
 except (OSError,UnicodeError):return "strict"
 return m.group(1) if m else "strict"
def approval(root):
 try:r=json.loads((root/APP).read_text());now=time.time();d=hashlib.sha256((root/PLAN).read_bytes()).hexdigest()
 except (OSError,ValueError,TypeError,KeyError):return False
 return isinstance(r.get("approved_at"),(int,float)) and r["approved_at"]<=now+60 and now-r["approved_at"]<=3600 and r.get("plan_sha256")==d
def scopes(text,root):
 try:lines=text.splitlines();start=lines.index("## 允許修改範圍")+1
 except ValueError:return []
 out=[]
 for line in lines[start:]:
  if line.startswith("## "):break
  if line.strip().startswith("- "):
   raw=line.strip()[2:].strip().strip("`"); directory=raw.endswith("/"); p=(root/raw).resolve()
   try:p.relative_to(root)
   except ValueError:return []
   out.append((p,directory))
 return out
def in_scope(target,allowed):
 for p,d in allowed:
  if target==p:return True
  if d:
   try:target.relative_to(p);return True
   except ValueError:pass
 return False
def strict_bash(c):
 if UNSAFE.search(c):return False
 try:t=shlex.split(c)
 except ValueError:return False
 return t[:2] in (["npm","test"],["dotnet","test"],["dotnet","build"]) or (len(t)>1 and t[0]=="bash" and t[1].startswith("tests/"))
def main():
 e=load_event(sys.stdin);root=project_root(e);tool=e["tool_name"];i=e["tool_input"];m=mode(root);target=None
 if tool=="Bash":
  c=i.get("command","")
  if ".codex/guardrail" in c:deny("管理檔不得透過 Bash 變更。")
  if m=="strict" and not strict_bash(c):deny("strict 模式禁止一般 Bash。")
 elif tool in PATHS:
  raw=i.get(PATHS[tool],"")
  if not raw:deny("計畫閘門：缺少目標路徑。")
  target=(root/raw).resolve() if not str(raw).startswith("/") else __import__('pathlib').Path(raw).resolve()
  if target==(root/APP).resolve() or target==(root/POL).resolve():deny("核准與政策檔只能由人類操作。")
  if target==(root/PLAN).resolve():return
 else:return
 try:text=(root/PLAN).read_text()
 except (OSError,UnicodeError):deny("計畫閘門：找不到拆解文件。")
 missing=[x for x in MARKERS if x not in text]
 if missing:deny("計畫閘門：拆解文件缺少必要標記。")
 if m!="light" and target is not None and not in_scope(target,scopes(text,root)):deny("計畫閘門：目標不在計畫允許修改範圍。")
 if m=="strict" and not approval(root):deny("計畫閘門：尚未取得有效核准或計畫已變更。")
if __name__=="__main__":main()
