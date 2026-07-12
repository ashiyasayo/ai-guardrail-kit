#!/usr/bin/env python3
"""
block_secrets.py — 憑證硬寫攔截 hook（對應團隊規範：禁止 hardcode 憑證）

事件：PreToolUse
matcher：Write|Edit|MultiEdit|NotebookEdit|Bash

行為：
- 掃描即將寫入的內容，偵測疑似硬寫的 API Key、Token、密碼、私鑰
- 命中即攔截（exit 2），並提示改用環境變數或 Secret Manager
- 為降低誤判：明顯的佔位符（如 YOUR_API_KEY、<token>、${VAR}）不攔截

exit code 語意：0 = 放行；2 = 攔截（stderr 回饋給模型）
"""
import json
import re
import sys

# 疑似憑證的偵測樣式（規則名稱, 正規表示式）
SECRET_PATTERNS = (
    ("AWS Access Key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("私鑰區塊", re.compile(r"-----BEGIN\s+(RSA|EC|OPENSSH|DSA|PGP)?\s*PRIVATE KEY-----")),
    ("GitHub Token", re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}")),
    ("Slack Token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("Cloudflare API Token", re.compile(r"(?i)cloudflare[_-]?(api[_-]?)?token['\"]?\s*[:=]\s*['\"][A-Za-z0-9_-]{30,}['\"]")),
    ("一般憑證指派", re.compile(r"(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|connection[_-]?string)\b\s*[:=]\s*['\"][^'\"\s]{8,}['\"]")),
    # 連線字串的 Password=／Pwd=（無空白，如 Server=db;Password=secret;）。
    # 刻意要求 = 前後無空白，避免誤中程式碼中的 `password = os.environ[...]`。
    ("MSSQL/MySQL 連線字串含密碼", re.compile(r"(?i)\b(?:Password|Pwd)=([^;'\"\s]{6,})(?=[;'\"\s]|$)")),
)

# 佔位符樣式：命中憑證但值屬佔位符時放行，降低誤判
PLACEHOLDER_PATTERN = re.compile(
    r"(?i)(YOUR_|CHANGE_?ME|PLACEHOLDER|EXAMPLE|<[^>]+>|\$\{[^}]+\}|%\([^)]+\)s|\{\{[^}]+\}\}|REPLACE_ME|xxx+|\*{3,})"
)

# 未加引號的憑證字面值（.env／YAML／設定檔最常見的硬寫方式，且上列規則多要求引號）：
# 鍵名含機密關鍵字（允許底線／連字號前綴，如 DB_PASSWORD、MY_API_KEY），
# 值為未加引號的連續字元。僅在值「看起來像憑證字面值」時攔截，
# 避免誤中程式碼中的環境變數參照或函式呼叫（如 password = os.environ["X"]）。
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


def extract_pending_content(tool_input: dict) -> str:
    """彙整即將寫入或執行的所有文字內容：
    Write 的 content、Edit 的 new_string、NotebookEdit 的 new_source、
    Bash 的 command，以及 MultiEdit 的每個 new_string。"""
    parts = []
    for key in ("content", "new_string", "new_source", "command"):
        if isinstance(tool_input.get(key), str):
            parts.append(tool_input[key])
    # MultiEdit：edits 陣列中的每個 new_string
    for edit in tool_input.get("edits", []) or []:
        if isinstance(edit, dict) and isinstance(edit.get("new_string"), str):
            parts.append(edit["new_string"])
    return "\n".join(parts)


def find_secret(content: str):
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


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("block_secrets: 無法解析 hook 輸入 JSON，保守攔截。", file=sys.stderr)
        sys.exit(2)

    content = extract_pending_content(hook_input.get("tool_input", {}))
    if not content:
        sys.exit(0)

    hit = find_secret(content)
    if hit is None:
        sys.exit(0)

    rule_name, _ = hit  # 刻意不輸出命中行內容，避免憑證出現在對話紀錄中
    print(
        f"憑證攔截：偵測到疑似硬寫的憑證（類型：{rule_name}），已攔截本次寫入。"
        "依團隊規範，敏感設定值須透過環境變數或 Secret Manager 管理，"
        "請改以環境變數引用（如 os.environ / IConfiguration / env()）重寫此段。"
        "若該值為已洩漏的真實憑證，請立即通知人類撤銷並重新核發。",
        file=sys.stderr,
    )
    sys.exit(2)


if __name__ == "__main__":
    main()
