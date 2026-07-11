#!/usr/bin/env python3
import sys
from hook_protocol import deny,load_event
from security_checks import dangerous_command
e=load_event(sys.stdin)
if e["tool_name"]=="exec_command":
 k=dangerous_command(e["tool_input"].get("cmd",""))
 if k:deny("危險指令攔截："+k)
