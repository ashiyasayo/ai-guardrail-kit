"""在 Codex thread 開始時注入 integrated-harness 操作提醒。"""

from __future__ import annotations

import json
import os
from pathlib import Path


PLAN_DRAFT = """## 已知資訊

- Codex integrated-harness 已在 thread 開始時建立本草稿。

## 缺少的資訊

- 尚待依使用者要求補充實作範圍與驗收方式。

【假設】在完成任務分析前，只允許修改本拆解文件。

## 允許修改範圍

- `.guardrail/plan/decomposition.md` — 僅允許先完善本計畫草稿
"""


REMINDER = """【護欄提醒 · integrated-harness】
修改檔案前先完善 .guardrail/plan/decomposition.md，內容須包含：
## 已知資訊、## 缺少的資訊、【假設】、## 允許修改範圍。
這是固定的閘門控制文件，不得改用一般 .docs/ 計畫文件。SessionStart 會在安全時自動建立
最小草稿；strict／standard 必須先依任務完善草稿，不要要求人工代建。
需要操作核准時，先自行建立 .guardrail/approval-requests/<operation SHA-256>.diff，再請人類審閱核准；不得要求人類代建 patch 檔。
strict／standard 在確定性檢查通過後須人類終端機一次性核准；light 僅可直接套用人類計畫範圍內的 apply_patch。
strict／standard 可單獨修改計畫草稿；light 計畫、政策及核准憑證不得由模型修改。
危險指令、明文憑證與個資防線不因核准模式而停用。
"""

def find_reasoning_protocol():
    """尋找隨 plugin 發佈的協定文件；找不到時回傳 None。"""
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = []
    plugin_root = os.environ.get("CODEX_PLUGIN_ROOT")
    if plugin_root:
        candidates.append(os.path.join(plugin_root, "reasoning-protocol.md"))
    candidates.append(os.path.join(os.path.dirname(here), "reasoning-protocol.md"))
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    return None


def build_reminder():
    """建立基本提醒，並安全附加受信任的 plugin 協定文件。"""
    protocol_path = find_reasoning_protocol()
    if not protocol_path:
        return REMINDER
    try:
        with open(protocol_path, encoding="utf-8") as handle:
            return REMINDER + "\n---\n" + handle.read()
    except (OSError, UnicodeError):
        return REMINDER


def initialize_plan() -> str:
    """安全建立最小計畫草稿；既有檔案與不可信路徑一律不覆寫。"""
    raw_root = os.environ.get("AI_GUARDRAIL_PROJECT_ROOT")
    if not raw_root:
        return "未建立拆解草稿：缺少專案根目錄。"
    try:
        root = Path(raw_root).resolve(strict=True)
        if not root.is_dir():
            raise OSError("專案根目錄不是目錄")
        guardrail = root / ".guardrail"
        plan_dir = guardrail / "plan"
        for candidate in (guardrail, plan_dir):
            if candidate.exists() and candidate.is_symlink():
                raise OSError("計畫目錄不得是符號連結")
        plan_dir.mkdir(parents=True, exist_ok=True)
        plan = plan_dir / "decomposition.md"
        plan.resolve().relative_to(root)
        with plan.open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(PLAN_DRAFT)
        return "已自動建立 .guardrail/plan/decomposition.md 最小草稿，請先依任務完善內容。"
    except FileExistsError:
        return "已保留既有 .guardrail/plan/decomposition.md。"
    except (OSError, UnicodeError, ValueError) as exc:
        return f"未建立拆解草稿：{exc}。請勿要求人工代建，改用獨立 apply_patch 建立。"


def main() -> None:
    message = initialize_plan() + "\n\n" + build_reminder()
    print(json.dumps({"systemMessage": message}, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
