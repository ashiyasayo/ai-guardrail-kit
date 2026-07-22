#!/usr/bin/env python3
"""Codex 紅線指令與明文憑證的單一程序 dispatcher。"""

import sys

from hook_protocol import deny, load_event
from security_checks import dangerous_command, pending_content, secret_kind


def main() -> None:
    event = load_event(sys.stdin)
    tool_input = event["tool_input"]
    if event["tool_name"] == "exec_command":
        kind = dangerous_command(tool_input.get("cmd", ""))
        if kind:
            deny("危險指令攔截：" + kind)
    kind = secret_kind(pending_content(tool_input))
    if kind:
        deny(kind)


if __name__ == "__main__":
    main()
