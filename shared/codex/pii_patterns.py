"""Generated distribution copy; source: shared/codex/pii_patterns.py."""

from __future__ import annotations

import re
from typing import Callable, Match, Pattern, Tuple


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


Rule = Tuple[str, Pattern[str], Callable[[Match[str]], str]]
RULES: Tuple[Rule, ...] = (
    ("台灣身分證字號", re.compile(r"\b[A-Z][12]\d{8}\b"), _mask_id),
    ("手機號碼", re.compile(r"\b09\d{2}[- ]?\d{3}[- ]?\d{3}\b"), _mask_mobile),
    ("Email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), _mask_email),
    ("地址", re.compile(r"[一-龥]{2,3}(?:縣|市)[一-龥]{0,6}(?:區|鄉|鎮|市)?[一-龥0-9]{0,10}(?:路|街|大道)(?:[一二三四五六七八九十]+段)?\d{1,4}號"), _mask_address),
    ("信用卡卡號", re.compile(r"\b\d{4}[- ]\d{4}[- ]\d{4}[- ]\d{1,4}\b"), _mask_credit_card),
)
