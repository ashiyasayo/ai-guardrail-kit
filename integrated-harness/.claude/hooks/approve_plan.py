#!/usr/bin/env python3
"""由人類在自己的終端機執行，將核准綁定目前拆解文件內容。"""
import argparse
import hashlib
import json
import os
import sys
import time

def main() -> int:
    parser = argparse.ArgumentParser(description="核准目前 Claude 專案的拆解文件。")
    parser.add_argument(
        "--project-dir",
        help="目前 Claude session 的專案根目錄絕對路徑。",
    )
    args = parser.parse_args()

    if args.project_dir and not os.path.isabs(args.project_dir):
        parser.error("--project-dir 必須是絕對路徑")

    # 顯式參數代表目前 session 根目錄，不受人類終端 cwd 或繼承環境變數影響。
    root = args.project_dir or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    root = os.path.realpath(os.path.abspath(root))
    plan = os.path.join(root, ".claude", "plan", "decomposition.md")
    approval = os.path.join(root, ".claude", ".plan_approved")

    try:
        with open(plan, "rb") as handle:
            digest = hashlib.sha256(handle.read()).hexdigest()
    except OSError as exc:
        print(f"無法讀取拆解文件：{plan}（{exc}）", file=sys.stderr)
        return 1

    record = {"plan_sha256": digest, "approved_at": time.time()}
    try:
        with open(approval, "w", encoding="utf-8") as handle:
            json.dump(record, handle)
            handle.write("\n")
    except OSError as exc:
        print(f"無法寫入核准紀錄：{approval}（{exc}）", file=sys.stderr)
        return 1

    print(f"已核准目前拆解文件，有效 60 分鐘：{approval}")
    return 0


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

if __name__ == "__main__":
    raise SystemExit(main())
