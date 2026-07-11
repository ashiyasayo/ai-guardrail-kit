import json
from pathlib import Path

def deny(reason):
    print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":reason}}, ensure_ascii=False))
    raise SystemExit(0)

def load_event(stream):
    try: event=json.load(stream)
    except (OSError, UnicodeError, RecursionError, TypeError, ValueError): deny("Invalid Codex hook input")
    required=("cwd","hook_event_name","model","permission_mode","session_id","tool_input","tool_name","tool_use_id","transcript_path","turn_id")
    if not isinstance(event,dict) or any(k not in event for k in required) or event.get("hook_event_name")!="PreToolUse" or not isinstance(event.get("tool_input"),dict): deny("Invalid Codex hook input")
    return event

def project_root(event):
    try: root=Path(event["cwd"]).resolve(strict=True)
    except (KeyError,OSError,RuntimeError): deny("Invalid Codex project root")
    if not root.is_dir(): deny("Invalid Codex project root")
    return root
