"""憑證硬寫偵測規則（Copilot 分支）。

規則本體與 Claude 版 `block_secrets.py` 為刻意分歧的平行分支——兩邊的 hook 輸入
形狀不同（Claude 依 tool_name 對應欄位；Copilot 由呼叫端遞迴收集所有字串後傳入
純文字），故不納入 shared 同步，改由行為 parity 測試守護判定一致。

修補任一邊的繞過手法時，須檢查另一邊是否需同步移植。
"""
from __future__ import annotations

import re
from typing import Optional, Tuple

# 疑似憑證的偵測樣式（規則名稱, 正規表示式）
SECRET_PATTERNS = (
    ("AWS Access Key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("私鑰區塊", re.compile(r"-----BEGIN\s+(RSA|EC|OPENSSH|DSA|PGP)?\s*PRIVATE KEY-----")),
    ("GitHub Token", re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}")),
    ("Slack Token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("Cloudflare API Token", re.compile(r"(?i)cloudflare[_-]?(api[_-]?)?token['\"]?\s*[:=]\s*['\"][A-Za-z0-9_-]{30,}['\"]")),
    ("一般憑證指派", re.compile(r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|connection[_-]?string)\b\s*[:=]\s*['\"][^'\"\s]{8,}['\"]")),
    # 連線字串中無空白的密碼欄位指派（形如 Server=db 之後緊接的密碼欄位）。
    # 刻意要求 = 前後無空白，避免誤中程式碼中以環境變數取值的指派寫法。
    ("MSSQL/MySQL 連線字串含密碼", re.compile(r"(?i)\b(?:Password|Pwd)=([^;'\"\s]{6,})(?=[;'\"\s]|$)")),
)

# 佔位符樣式：命中憑證但值屬佔位符時放行，降低誤判
PLACEHOLDER_PATTERN = re.compile(
    r"(?i)(YOUR_|CHANGE_?ME|PLACEHOLDER|EXAMPLE|<[^>]+>|\$\{[^}]+\}|%\([^)]+\)s|\{\{[^}]+\}\}|REPLACE_ME|xxx+|\*{3,})"
)

# 未加引號的憑證字面值（.env／YAML／設定檔最常見的硬寫方式，且上列規則多要求引號）：
# 鍵名含機密關鍵字（允許底線／連字號前綴，如 DB_PASSWORD、MY_API_KEY），
# 值為未加引號的連續字元。僅在值「看起來像憑證字面值」時攔截，
# 避免誤中程式碼中的環境變數參照或函式呼叫。
UNQUOTED_ASSIGNMENT_PATTERN = re.compile(
    r"(?i)(?:[A-Za-z0-9]+[_-])*(?:password|passwd|pwd|secret|api[_-]?key|access[_-]?token"
    r"|auth[_-]?token|client[_-]?secret|token)\s*[:=]\s*([^\s'\"`;&|#]{8,})"
)

# 值屬環境變數／設定參照或函式呼叫時的前綴（大小寫不敏感），視為安全參照不攔截
REFERENCE_VALUE_PREFIXES = (
    "os.environ", "process.env", "getenv", "system.getenv",
    "environment.", "config.", "env.", "settings.", "vault.",
)


def looks_like_secret_literal(value: str) -> bool:
    """判斷未加引號的指派值是否像硬寫的憑證字面值（而非變數／函式／佔位符參照）。"""
    if PLACEHOLDER_PATTERN.search(value):
        return False
    if value.startswith("$"):                      # $VAR、${VAR}
        return False
    if any(ch in value for ch in "()[]"):           # 函式呼叫或索引存取
        return False
    if value.lower().startswith(REFERENCE_VALUE_PREFIXES):
        return False
    # 保守判斷：要求同時含字母與數字，濾掉純識別字（如 user_input、getSecret）
    if not (any(c.isdigit() for c in value) and any(c.isalpha() for c in value)):
        return False
    return True


def find_secret(content: str) -> Optional[Tuple[str, str]]:
    """回傳第一個命中的（規則名稱, 命中行內容），未命中回傳 None。"""
    for line in content.splitlines():
        for rule_name, pattern in SECRET_PATTERNS:
            hit = pattern.search(line)
            # 佔位符判斷以命中片段為準，避免同一列的佔位符掩蓋真憑證
            if hit and not PLACEHOLDER_PATTERN.search(hit.group(0)):
                return rule_name, line.strip()
        # 未加引號的憑證字面值（涵蓋引號規則抓不到的 .env／YAML 寫法）
        for hit in UNQUOTED_ASSIGNMENT_PATTERN.finditer(line):
            if looks_like_secret_literal(hit.group(1)):
                return "未加引號的憑證指派", line.strip()
    return None


def check_content(content: str) -> Optional[str]:
    """回傳阻擋原因；None 表示放行。不做任何 I/O。

    說明文字以英文撰寫、規則名稱沿用與 Claude 版一致的中文（供 parity 測試比對）。
    出站會以 ensure_ascii 轉義中文，仍是合法 JSON。刻意不輸出命中行內容，
    避免憑證出現在對話紀錄中。
    """
    if not content:
        return None
    hit = find_secret(content)
    if hit is None:
        return None
    rule_name, _ = hit  # 刻意不輸出命中行內容，避免憑證出現在對話紀錄中
    return (
        f"Secret blocked: detected a hardcoded credential (rule: {rule_name}). "
        "Move the value to an environment variable or a secret manager and "
        "reference it instead. If this is a real leaked credential, tell a "
        "human to revoke and reissue it now."
    )
