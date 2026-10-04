#!/usr/bin/env python3
"""保留舊發佈入口；事件格式仍由共用協定正規化。"""
import sys
from hook_protocol import deny, load_event
from security_checks import dangerous_command

event = load_event(sys.stdin)
if event["tool_name"] == "Bash":
    kind = dangerous_command(event["tool_input"]["command"])
    if kind:
        deny("危險指令攔截：" + kind)
