#!/usr/bin/env python3
import re
import shlex
import sys
from hook_protocol import ask, deny, load_event, project_root

UNSAFE = re.compile(
    r"[;&|><`\n\r*?\[\]]|\$\(|\btee\b|\bxargs\b|"
    r"-(?:delete|exec|execdir|ok|okdir|fprint|fprintf|fls)\b"
)
READ = {"ls", "cat", "head", "tail", "grep", "rg", "pwd", "which", "file", "wc", "diff", "stat", "du", "ps", "printenv"}
GIT_READ = {"status", "log", "diff", "show", "rev-parse"}
DISALLOWED_READ_FLAGS = {"--pre", "--hostname-bin", "--ext-diff", "--textconv", "--output"}

def readonly(cmd):
    if not isinstance(cmd, str) or UNSAFE.search(cmd): return False
    try: tokens = shlex.split(cmd)
    except ValueError: return False
    if not tokens: return False
    if any(token.split("=", 1)[0] in DISALLOWED_READ_FLAGS for token in tokens[1:]): return False
    if tokens[0] in READ: return True
    if len(tokens) > 1 and tokens[0] == "git" and tokens[1] in GIT_READ: return True
    if tokens[:2] == ["git", "branch"]:
        return len(tokens) == 2 or all(token in {"--list", "--show-current", "-a", "-r", "-v", "-vv"} for token in tokens[2:])
    return False

def main():
    event = load_event(sys.stdin); project_root(event)
    tool, data = event["tool_name"], event["tool_input"]
    if tool == "exec_command":
        cmd = data.get("cmd")
        if readonly(cmd): return
        if not isinstance(cmd, str): deny("Malformed native exec_command payload.")
        ask("Harness requires native Codex approval for this command.")
    if tool == "apply_patch":
        if not isinstance(data.get("patch"), str): deny("Malformed native apply_patch payload.")
        ask("Harness requires native Codex approval for this patch.")
    deny("Unknown tool is not proven read-only.")

if __name__ == "__main__": main()
