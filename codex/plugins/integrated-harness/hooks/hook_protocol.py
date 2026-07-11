import json
from pathlib import Path
def deny(reason): print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":reason}},ensure_ascii=False));raise SystemExit(0)
def load_event(s):
 try:e=json.load(s)
 except (OSError,UnicodeError,RecursionError,TypeError,ValueError):deny("Invalid Codex hook input")
 if not isinstance(e,dict) or e.get("hook_event_name")!="PreToolUse" or not isinstance(e.get("tool_input"),dict):deny("Invalid Codex hook input")
 return e
def project_root(e):
 try:r=Path(e["cwd"]).resolve(strict=True)
 except (KeyError,OSError,RuntimeError):deny("Invalid Codex project root")
 if not r.is_dir():deny("Invalid Codex project root")
 return r
