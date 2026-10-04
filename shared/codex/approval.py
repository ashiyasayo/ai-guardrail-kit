"""人類終端機核准：受保護的短效、一次性操作憑證；hook 不建立授權。"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import sys
import tempfile
import time
from pathlib import Path

from hook_protocol import deny, normalize_event

TTL_SECONDS = 600
PLAN = ".guardrail/plan/decomposition.md"
POLICY = ".codex/guardrail/orchestration-policy.md"


def codex_home():
    return Path(os.environ.get("CODEX_HOME", str(Path(os.environ.get("HOME", str(Path.home()))) / ".codex"))).resolve()


def approval_directory(project):
    directory = codex_home() / "guardrail" / "approvals"
    # 核准庫不得落在模型的一般工作區；.codex 的平台保護仍是必要信任邊界。
    try:
        directory.relative_to(project)
    except ValueError:
        pass
    else:
        raise ValueError("CODEX_HOME approval store must be outside the project")
    for item in (directory, *directory.parents):
        if item.is_symlink():
            raise ValueError("approval store must not contain symlinks")
    return directory


def digest_file(path, required=False):
    if not path.exists() and not required:
        return None
    if path.is_symlink() or not path.is_file():
        raise ValueError("approval context must be a regular file")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def operation(event, project, mode):
    normalized = normalize_event(event)
    if mode not in ("harness", "integrated-harness"):
        raise ValueError("mode does not use operation approvals")
    tool = normalized.get("tool_name")
    if tool not in ("Bash", "apply_patch"):
        raise ValueError("unsupported approval tool")
    policy = project / POLICY
    if not policy.exists():
        policy = codex_home() / "guardrail/orchestration-policy.md"
    cwd = Path(event.get("cwd", str(project))).resolve(strict=True)
    cwd.relative_to(project)
    if not cwd.is_dir():
        raise ValueError("operation cwd must be a directory")
    executable_input = dict(normalized["tool_input"])
    # 宿主可能補上 null／文字說明；這不是執行參數，不應讓 --command 核准失配。
    executable_input.pop("description", None)
    context = {"project": str(project), "mode": mode, "tool": tool,
               "input": executable_input, "cwd": str(cwd),
               "plan_sha256": digest_file(project / PLAN, mode == "integrated-harness"),
               "policy_sha256": digest_file(policy) if mode == "integrated-harness" else None}
    digest = hashlib.sha256(json.dumps(context, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")).hexdigest()
    return digest, context


def grant(event, project, mode, confirmed_digest):
    digest, context = operation(event, project, mode)
    if confirmed_digest != digest:
        raise ValueError("confirmation digest does not match the current operation and plan")
    directory = approval_directory(project)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = directory / (digest + ".json")
    if target.is_symlink():
        raise ValueError("approval file must not be a symlink")
    now = time.time()
    receipt = {"schema_version": 1, "digest": digest, "issued_at": now, "expires_at": now + TTL_SECONDS}
    fd, name = tempfile.mkstemp(prefix=".approval-", dir=str(directory))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(receipt, handle)
        os.replace(name, target)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    return digest


def require_approval(event, project, mode):
    """原子取得消耗權；無法寫入受保護核准庫時 fail closed。"""
    try:
        digest, _ = operation(event, project, mode)
        directory = approval_directory(project)
        receipt_path = directory / (digest + ".json")
        lock = directory / (digest + ".lock")
        if not receipt_path.exists():
            deny("需要人類終端機核准（10 分鐘、一次性）；operation SHA-256: " + digest)
        fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
        try:
            if receipt_path.is_symlink() or not stat.S_ISREG(receipt_path.stat().st_mode):
                raise ValueError("invalid approval receipt")
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            now = time.time()
            issued, expires = receipt.get("issued_at"), receipt.get("expires_at")
            if (receipt.get("schema_version") != 1 or receipt.get("digest") != digest
                    or type(issued) not in (int, float) or type(expires) not in (int, float)
                    or not (issued <= now < expires <= issued + TTL_SECONDS)):
                raise ValueError("expired or invalid approval receipt")
            receipt_path.unlink()
        finally:
            lock.unlink()
    except (OSError, ValueError, TypeError, AttributeError):
        deny("核准無效、已使用或核准庫不可寫；請由人類終端機重新檢查並核准。")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--mode", choices=("harness", "integrated-harness"), required=True)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--command")
    action.add_argument("--patch-file", type=Path)
    action.add_argument("--event-file", type=Path)
    parser.add_argument("--confirm", metavar="SHA256")
    args = parser.parse_args()
    try:
        project = Path(args.project).resolve(strict=True)
        if not project.is_dir():
            raise ValueError("project must be a directory")
        if args.event_file is not None:
            event = json.loads(args.event_file.read_text(encoding="utf-8"))
            if not isinstance(event, dict):
                raise ValueError("event must be an object")
        else:
            command = args.command if args.command is not None else args.patch_file.read_text(encoding="utf-8")
            event = {"tool_name": "Bash" if args.command is not None else "apply_patch", "tool_input": {"command": command}}
        digest, context = operation(event, project, args.mode)
        # JSON 跳脫控制字元，避免待審命令操控終端機顯示。
        print(json.dumps(context, ensure_ascii=True, indent=2))
        if args.confirm is None:
            print("Human review required. Re-run in your own terminal with --confirm " + digest)
            return 0
        grant(event, project, args.mode, args.confirm)
        print("Approved for one matching operation within 10 minutes: " + digest)
        return 0
    except (OSError, ValueError):
        print("Approval failed: context changed, path unsafe or store unavailable", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
