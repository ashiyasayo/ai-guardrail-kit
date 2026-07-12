#!/usr/bin/env python3
"""由人類在自己的終端機執行，將核准綁定目前拆解文件內容。"""
import hashlib
import json
import os
import time

ROOT = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
PLAN = os.path.join(ROOT, ".claude", "plan", "decomposition.md")
APPROVAL = os.path.join(ROOT, ".claude", ".plan_approved")

with open(PLAN, "rb") as handle:
    digest = hashlib.sha256(handle.read()).hexdigest()

record = {"plan_sha256": digest, "approved_at": time.time()}
with open(APPROVAL, "w", encoding="utf-8") as handle:
    json.dump(record, handle)
    handle.write("\n")

print(f"已核准目前拆解文件，有效 60 分鐘：{APPROVAL}")
