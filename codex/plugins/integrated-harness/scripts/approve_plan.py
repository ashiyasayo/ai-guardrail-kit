#!/usr/bin/env python3
import hashlib,json,sys,time
from pathlib import Path
root=Path(sys.argv[1] if len(sys.argv)>1 else ".").resolve();plan=root/".codex/guardrail/plan/decomposition.md";out=root/".codex/guardrail/approval.json"
out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps({"plan_sha256":hashlib.sha256(plan.read_bytes()).hexdigest(),"approved_at":int(time.time())},separators=(",",":"))+"\n")
