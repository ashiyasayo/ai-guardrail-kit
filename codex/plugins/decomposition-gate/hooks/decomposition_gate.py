#!/usr/bin/env python3
import re, sys
from hook_protocol import deny, load_event, project_root

PLAN=".codex/guardrail/plan/decomposition.md"
MARKERS=("## 已知資訊","## 缺少的資訊","【假設】")
WRITES={"Write":"file_path","Edit":"file_path","MultiEdit":"file_path","NotebookEdit":"notebook_path"}
WRITE_RE=re.compile(r">{1,2}|(?:^|[|;&]\s*)(?:sudo\s+)?(?:rm|mv|cp|mkdir|touch)\b|\bsed\b[^|;&]*\s-[A-Za-z]*i|(?:^|\s)--(?:output|in-place)(?:[=\s]|$)")

def main():
    event=load_event(sys.stdin); root=project_root(event); tool=event["tool_name"]; inp=event["tool_input"]
    if tool in WRITES:
        target=inp.get(WRITES[tool],"")
        if target and str(target).replace("\\","/").endswith(PLAN): return
    elif tool=="Bash":
        command=inp.get("command","")
        if PLAN in command.replace("\\","/"): return
        if not isinstance(command,str) or not WRITE_RE.search(command): return
    else: return
    path=root/PLAN
    try: content=path.read_text()
    except (OSError,UnicodeError): deny("Plan gate: 找不到或無法讀取拆解產出物。")
    missing=[m for m in MARKERS if m not in content]
    if missing: deny("Plan gate: 拆解產出物不完整，缺少必要標記："+"、".join(missing))
if __name__=="__main__": main()
