#!/usr/bin/env python3
"""
pii_patterns.py — 個資偵測規則的單一事實來源。

供 redact_sensitive_info.py（PreToolUse，去識別化後放行）與
block_pii_prompt.py（UserPromptSubmit，整段阻擋）共用，避免兩層防線
各自維護一份規則造成漂移。本檔案不是 hook 進入點，不含任何 I/O。
"""
import re

TAIWAN_ID_PATTERN = re.compile(r"\b[A-Z][12]\d{8}\b")
MOBILE_PATTERN = re.compile(r"\b09\d{2}[- ]?\d{3}[- ]?\d{3}\b")
EMAIL_PATTERN = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")


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


# （規則名稱, 正規表示式, 遮罩函式）
RULES = (
    ("台灣身分證字號", TAIWAN_ID_PATTERN, _mask_id),
    ("手機號碼", MOBILE_PATTERN, _mask_mobile),
    ("Email", EMAIL_PATTERN, _mask_email),
)
