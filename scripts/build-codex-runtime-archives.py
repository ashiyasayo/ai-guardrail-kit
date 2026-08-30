#!/usr/bin/env python3
"""建立可重現的 Codex runtime archive，並可選擇更新 manifest。"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import tarfile
from pathlib import Path
from typing import Dict, Iterable, List


MODES = {
    "decomposition-gate": ["decomposition_gate.py", "hook_protocol.py"],
    "sensitive-data-guard": ["block_secrets.py", "pii_guard.py", "pii_patterns.py", "security_checks.py", "hook_protocol.py"],
    "harness": ["plan_gate.py", "security_guard.py", "pii_guard.py", "pii_patterns.py", "security_checks.py", "hook_protocol.py"],
    "integrated-harness": ["plan_gate.py", "security_guard.py", "pii_guard.py", "pii_patterns.py", "security_checks.py", "hook_protocol.py", "session_start.py"],
}


def archive(root: Path, mode: str, destination: Path) -> str:
    source = root / "codex" / "plugins" / mode / "hooks"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as bundle:
                for name in sorted(MODES[mode]):
                    path = source / name
                    info = bundle.gettarinfo(str(path), arcname="hooks/" + name)
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mtime = 0
                    info.mode = 0o644
                    with path.open("rb") as stream:
                        bundle.addfile(info, stream)
                if mode == "integrated-harness":
                    path = root / "codex" / "plugins" / mode / "orchestration-policy.md"
                    info = bundle.gettarinfo(str(path), arcname="orchestration-policy.md")
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mtime = 0
                    info.mode = 0o644
                    with path.open("rb") as stream:
                        bundle.addfile(info, stream)
    return hashlib.sha256(destination.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8")) if args.manifest else None
    for mode in MODES:
        path = args.output / ("codex-runtime-" + mode + ".tar.gz")
        digest = archive(args.root, mode, path)
        if manifest:
            item = manifest["modes"][mode]
            item["archive_sha256"] = digest
            item["archive_size"] = path.stat().st_size
    if manifest:
        args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
