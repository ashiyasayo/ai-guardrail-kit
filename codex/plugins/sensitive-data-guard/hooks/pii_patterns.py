"""Generated distribution copy; source: shared/codex/pii_patterns.py."""

from __future__ import annotations

import re
from typing import Callable, Match, Optional, Pattern, Tuple


TAIWAN_ID_PATTERN = re.compile(r"\b[A-Z][12]\d{8}\b")
MOBILE_PATTERN = re.compile(r"\b09\d{2}[- ]?\d{3}[- ]?\d{3}\b")
EMAIL_PATTERN = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
TAIWAN_ADDRESS_PATTERN = re.compile(
    r"[一-龥]{2,3}(?:縣|市)[一-龥]{0,6}(?:區|鄉|鎮|市)?"
    r"[一-龥0-9]{0,10}(?:路|街|大道)(?:[一二三四五六七八九十]+段)?\d{1,4}號"
)
CREDIT_CARD_PATTERN = re.compile(r"\b\d(?:[ -]?\d){12,18}\b")
STUDENT_ID_PATTERN = re.compile(
    r"(?i)(學號|學生證號|student\s*(?:id|number))([\s:：#]*)([A-Za-z]?\d{6,10})(?!\d)"
)
PASSPORT_PATTERN = re.compile(
    r"(?i)(護照(?:號碼|號)?|passport(?:\s*(?:no\.?|number))?)([\s:：#]*)(\d{8,9})(?!\d)"
)


def _mask_id(match: Match[str]) -> str:
    value = match.group(0)
    return value[:2] + "*" * (len(value) - 3) + value[-1]


def _mask_mobile(match: Match[str]) -> str:
    digits = re.sub(r"[^0-9]", "", match.group(0))
    return digits[:4] + "***" + digits[-3:]


def _mask_email(match: Match[str]) -> str:
    local, _, domain = match.group(0).partition("@")
    return local[0] + "*" * max(len(local) - 1, 1) + "@" + domain


def _mask_address(match: Match[str]) -> str:
    value = match.group(0)
    keep = re.match(r"[一-龥]{2,3}(?:縣|市)[一-龥]{0,6}(?:區|鄉|鎮|市)?", value)
    prefix = keep.group(0) if keep else value[:3]
    return prefix + "＊" * max(len(value) - len(prefix), 1)


def _mask_credit_card(match: Match[str]) -> str:
    digits = re.sub(r"[^0-9]", "", match.group(0))
    return digits[:4] + " **** **** " + digits[-4:]


def _mask_labeled_number(match: Match[str]) -> str:
    label, separator, number = match.group(1), match.group(2), match.group(3)
    return label + separator + number[:1] + "*" * max(len(number) - 1, 1)


def _luhn_valid(match: Match[str]) -> bool:
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


Validator = Optional[Callable[[Match[str]], bool]]
Rule = Tuple[str, Pattern[str], Callable[[Match[str]], str], Validator]
RULES: Tuple[Rule, ...] = (
    ("台灣身分證字號", TAIWAN_ID_PATTERN, _mask_id, None),
    ("手機號碼", MOBILE_PATTERN, _mask_mobile, None),
    ("Email", EMAIL_PATTERN, _mask_email, None),
    ("地址", TAIWAN_ADDRESS_PATTERN, _mask_address, None),
    ("信用卡卡號", CREDIT_CARD_PATTERN, _mask_credit_card, _luhn_valid),
    ("學號", STUDENT_ID_PATTERN, _mask_labeled_number, None),
    ("護照號碼", PASSPORT_PATTERN, _mask_labeled_number, None),
)
