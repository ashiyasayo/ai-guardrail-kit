#!/usr/bin/env python3
"""
pii_patterns.py — 個資偵測規則的單一事實來源。

供 redact_sensitive_info.py（PreToolUse，去識別化後放行）與
block_pii_prompt.py（UserPromptSubmit，整段阻擋）共用，避免兩層防線
各自維護一份規則造成漂移。本檔案不是 hook 進入點，不含任何 I/O。

規則以「regex 是否命中」判定，不含如信用卡 Luhn checksum 之類需要額外驗證
邏輯的規則類型（會破壞 RULES 與呼叫端「命中即遮罩／阻擋」的簡單契約）；
信用卡卡號規則因此限定為「有分隔符號分組」的格式，降低誤判。
學號、護照號碼未納入規則：學號格式與身分證字號高度重疊（如 R10921001），
護照號碼為純數字缺乏可辨識結構，兩者皆會造成大量誤判，故暫不新增，
仍屬已知限制（見 harness/MAINTENANCE.md、integrated-harness/MAINTENANCE.md）。
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
# 信用卡卡號：限定 4-4-4-4 分隔格式（含空白或連字號），未分隔的純數字不比對，
# 以免誤判一般長數字（如訂單編號）
CREDIT_CARD_PATTERN = re.compile(r"\b\d{4}[- ]\d{4}[- ]\d{4}[- ]\d{1,4}\b")


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


# （規則名稱, 正規表示式, 遮罩函式）
RULES = (
    ("台灣身分證字號", TAIWAN_ID_PATTERN, _mask_id),
    ("手機號碼", MOBILE_PATTERN, _mask_mobile),
    ("Email", EMAIL_PATTERN, _mask_email),
    ("地址", TAIWAN_ADDRESS_PATTERN, _mask_address),
    ("信用卡卡號", CREDIT_CARD_PATTERN, _mask_credit_card),
)
