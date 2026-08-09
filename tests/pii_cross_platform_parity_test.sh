#!/usr/bin/env bash
#
# 三平台 PII 規則行為一致性測試。
#
# 為何需要：Claude、Codex 與 Copilot 各自維護一份 pii_patterns.py 單一來源
# （平台 hook I/O 契約不同，無法共用同一檔案）。三份副本的正則與遮罩行為必須
# 完全一致，否則同一份個資在不同平台會有不同判定。此測試以共同語料驗證行為，
# 不依靠人工記憶維持一致（比照 block_secrets 已有的 parity 做法）。
#
# 【測試語料的寫法】語料以相鄰字串串接組出，使本檔內容不含連續的個資字面值——
# 否則本儲存庫自身的 redact_sensitive_info 會在寫入時靜默遮罩這些樣本，
# 導致語料失效而不易察覺。
set -euo pipefail

# Windows（Git Bash）通常只有 python 而無 python3，實際探測後回退
if ! python3 -V >/dev/null 2>&1 && python -V >/dev/null 2>&1; then
  python3() { python "$@"; }
fi
export PYTHONUTF8=${PYTHONUTF8:-1}

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo" <<'PYEOF'
import importlib.util
import sys
from pathlib import Path

repo = Path(sys.argv[1])

SOURCES = {
    "claude": repo / "shared" / "claude" / "pii_patterns.py",
    "codex": repo / "shared" / "codex" / "pii_patterns.py",
    "copilot": repo / "shared" / "copilot" / "pii_patterns.py",
}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


missing = [str(p) for p in SOURCES.values() if not p.is_file()]
if missing:
    print("FAIL: 找不到 PII 來源檔：" + "、".join(missing))
    raise SystemExit(1)

modules = {name: load("pii_patterns_" + name, path) for name, path in SOURCES.items()}


def hit_kinds(rules, text):
    """以規則契約計算命中種類（去重保序）——三平台共用同一演算法以做公平比較。"""
    found = []
    for kind, pattern, _mask, validator in rules:
        if kind in found:
            continue
        for match in pattern.finditer(text):
            if validator is None or validator(match):
                found.append(kind)
                break
    return found


def redact(rules, text):
    """依序套用全部規則的遮罩，比對遮罩輸出是否也完全一致。"""
    out = text
    for _kind, pattern, mask, validator in rules:
        def _sub(match, _mask=mask, _validator=validator):
            if _validator is not None and not _validator(match):
                return match.group(0)
            return _mask(match)
        out = pattern.sub(_sub, out)
    return out


# 語料：相鄰字串串接（見檔頭說明）。涵蓋七種個資與負向樣本。
SAMPLES = [
    ("身分證字號", "A" "123456789"),
    ("手機號碼", "0912" "345678"),
    ("手機號碼含分隔", "0912-" "345-678"),
    ("Email", "user" "@example.org"),
    ("地址", "台北市中正區" "重慶南路一段1號"),
    ("信用卡（Luhn 通過）", "4111" "111111111111"),
    ("長數字（Luhn 不通過）", "1234" "567890123456"),
    ("學號（標籤錨定）", "學號：" "B1234567"),
    ("護照（標籤錨定）", "護照號碼 " "123456789"),
    ("裸編號無標籤", "編號 " "B1234567"),
    ("無敏感資料", "print(1) and refactor the function"),
    (
        "多種混合",
        "contact " "user" "@example.org" " id " "A" "123456789"
        "\nphone " "0912" "345678" " card " "4111" "111111111111",
    ),
]

failures = []
for label, sample in SAMPLES:
    kinds = {name: hit_kinds(module.RULES, sample) for name, module in modules.items()}
    if len({tuple(value) for value in kinds.values()}) != 1:
        failures.append(f"{label}：命中種類不一致 {kinds}")

    masked = {name: redact(module.RULES, sample) for name, module in modules.items()}
    if len(set(masked.values())) != 1:
        failures.append(f"{label}：遮罩輸出不一致 {masked}")

    # Copilot 額外提供的 find_pii_kinds() 必須與規則契約算出的結果相同
    copilot_helper = modules["copilot"].find_pii_kinds(sample)
    if copilot_helper != kinds["copilot"]:
        failures.append(
            f"{label}：copilot find_pii_kinds 與 RULES 不一致 "
            f"{copilot_helper} != {kinds['copilot']}"
        )

if failures:
    print(f"FAIL: {len(failures)} 項不一致")
    for item in failures:
        print("  - " + item)
    raise SystemExit(1)

print(f"PASS: 三平台 PII 規則在 {len(SAMPLES)} 組語料上行為完全一致")
PYEOF
