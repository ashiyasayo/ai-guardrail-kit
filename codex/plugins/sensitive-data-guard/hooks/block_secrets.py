#!/usr/bin/env python3
import sys
from hook_protocol import deny,load_event
from security_checks import pending_content,secret_kind
e=load_event(sys.stdin); k=secret_kind(pending_content(e["tool_input"]))
if k:deny(k)

