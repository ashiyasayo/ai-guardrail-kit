#!/usr/bin/env python3
"""
pii_patterns.py — 個資偵測規則的單一事實來源。

供 redact_sensitive_info.py（PreToolUse，去識別化後放行）與
block_pii_prompt.py（UserPromptSubmit，整段阻擋）共用，避免兩層防線
各自維護一份規則造成漂移。本檔案不是 hook 進入點，不含任何 I/O。

規則契約（RULES）為 4-tuple：(名稱, 已編譯 regex, 遮罩函式, 驗證函式)。
判定命中 = regex 命中 AND（驗證函式為 None 或 驗證函式(match) 回傳 True）。
驗證函式讓需要額外邏輯的規則（如信用卡 Luhn checksum）也能納入，而不必
放寬 regex 造成大量誤判。

各規則設計取捨：
- 信用卡卡號：放寬為 13–19 碼（含連續無分隔），改以 Luhn checksum 過濾誤判。
- 學號、護照號碼：採「標籤錨定」——必須鄰近出現標籤關鍵字才觸發。台灣學號
  無全國統一格式且與身分證字號、任意編號高度重疊；ROC 護照為純數字且無公開
  檢查碼。裸偵測會造成大量誤判，故要求標籤，屬精確率優先的取捨，無法涵蓋
  無標籤的裸資料（見 harness/MAINTENANCE.md、integrated-harness/MAINTENANCE.md）。
"""
import re

TAIWAN_ID_PATTERN = re.compile(r"\b[A-Z][12]\d{8}\b")
MOBILE_PATTERN = re.compile(r"\b09\d{2}[- ]?\d{3}[- ]?\d{3}\b")
EMAIL_PATTERN = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
# 台灣地址：縣市＋（區／鄉／鎮／市）＋路／街／大道（可含段）＋門牌號
TAIWAN_ADDRESS_PATTERN = re.compile(
    r"[一-龥]{2,3}(?:縣|市)[一-龥]{0,6}(?:區|鄉|鎮|市)?"
    r"[一-龥0-9]{0,10}(?:路|街|大道)(?:[一二三四五六七八九十]+段)?\d{1,4}號"
)
# 信用卡卡號：13–19 碼，允許以單一空白或連字號分隔；實際有效性交由 Luhn 驗證，
# 避免誤判一般長數字（如訂單編號）
CREDIT_CARD_PATTERN = re.compile(r"\b\d(?:[ -]?\d){12,18}\b")
# 學號：標籤錨定（學號／學生證號／student id／student number）＋英數編號。
# 需要標籤才觸發，(?!\d) 確保編號未被更長的數字截斷。
STUDENT_ID_PATTERN = re.compile(
    r"(?i)(學號|學生證號|student\s*(?:id|number))([\s:：#]*)([A-Za-z]?\d{6,10})(?!\d)"
)
# 護照號碼：標籤錨定（護照／passport）＋8–9 碼數字。
PASSPORT_PATTERN = re.compile(
    r"(?i)(護照(?:號碼|號)?|passport(?:\s*(?:no\.?|number))?)([\s:：#]*)(\d{8,9})(?!\d)"
)


def _mask_id(match: re.Match) -> str:
    value = match.group(0)
    return value[:2] + "*" * (len(value) - 3) + value[-1]


def _mask_mobile(match: re.Match) -> str:
    digits = re.sub(r"[^0-9]", "", match.group(0))
    return digits[:4] + "*" * 3 + digits[-3:]


def _mask_email(match: re.Match) -> str:
    local, _, domain = match.group(0).partition("@")
    masked_local = local[0] + "*" * max(len(local) - 1, 1)
    return f"{masked_local}@{domain}"


def _mask_address(match: re.Match) -> str:
    value = match.group(0)
    # 保留縣市／行政區辨識度，門牌與路名細節遮罩
    keep = re.match(r"[一-龥]{2,3}(?:縣|市)[一-龥]{0,6}(?:區|鄉|鎮|市)?", value)
    prefix = keep.group(0) if keep else value[:3]
    return prefix + "＊" * max(len(value) - len(prefix), 1)


def _mask_credit_card(match: re.Match) -> str:
    digits = re.sub(r"[^0-9]", "", match.group(0))
    return digits[:4] + " **** **** " + digits[-4:]


def _mask_labeled_number(match: re.Match) -> str:
    """遮罩標籤錨定規則（學號／護照）的編號部分，保留標籤與分隔符與編號首字。"""
    label, separator, number = match.group(1), match.group(2), match.group(3)
    masked = number[:1] + "*" * max(len(number) - 1, 1)
    return f"{label}{separator}{masked}"


def _luhn_valid(match: re.Match) -> bool:
    """信用卡 Luhn checksum 驗證，過濾非卡號的長數字。"""
    digits = [int(char) for char in re.sub(r"[^0-9]", "", match.group(0))]
    if not 13 <= len(digits) <= 19:
        return False
    checksum = 0
    for index, digit in enumerate(reversed(digits)):
        if index % 2 == 1:
            digit *= 2
            if digit > 9:
                digit -= 9
        checksum += digit
    return checksum % 10 == 0


# （規則名稱, 正規表示式, 遮罩函式, 驗證函式）
# 驗證函式為 None 代表 regex 命中即算命中；否則需再通過驗證函式才算命中。
RULES = (
    ("台灣身分證字號", TAIWAN_ID_PATTERN, _mask_id, None),
    ("手機號碼", MOBILE_PATTERN, _mask_mobile, None),
    ("Email", EMAIL_PATTERN, _mask_email, None),
    ("地址", TAIWAN_ADDRESS_PATTERN, _mask_address, None),
    ("信用卡卡號", CREDIT_CARD_PATTERN, _mask_credit_card, _luhn_valid),
    ("學號", STUDENT_ID_PATTERN, _mask_labeled_number, None),
    ("護照號碼", PASSPORT_PATTERN, _mask_labeled_number, None),
)
