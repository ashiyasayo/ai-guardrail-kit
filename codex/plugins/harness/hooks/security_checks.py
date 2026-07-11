import re
DANGEROUS=(("遞迴強制刪除",re.compile(r"\brm\b(?=[^;&|]*\s(?:-[A-Za-z]*r[A-Za-z]*|--recursive))(?=[^;&|]*\s(?:-[A-Za-z]*f[A-Za-z]*|--force))")),("硬重置",re.compile(r"\bgit\s+reset\s+--hard\b")),("資料庫毀滅性操作",re.compile(r"(?i)\b(?:DROP\s+(?:TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)\b")),("下載即執行",re.compile(r"\b(?:curl|wget)\b[^|;&]*\|\s*(?:sudo\s+)?(?:bash|sh|python3?)\b")))
SECRETS=(("AWS Access Key",re.compile(r"AKIA[0-9A-Z]{16}")),("私鑰區塊",re.compile(r"-----BEGIN\s+(?:RSA|EC|OPENSSH|DSA|PGP)?\s*PRIVATE KEY-----")),("GitHub Token",re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}")),("一般憑證指派",re.compile(r"(?i)\b(?:password|secret|api[_-]?key|access[_-]?token)\b\s*[:=]\s*['\"][^'\"\s]{8,}['\"]")))
def dangerous_command(s):
 return next((n for n,p in DANGEROUS if isinstance(s,str) and p.search(s)),None)
def pending_content(i):
 if not isinstance(i,dict):return ""
 parts=[i[k] for k in ("content","new_string","new_source","command") if isinstance(i.get(k),str)]
 parts += [e["new_string"] for e in (i.get("edits") or []) if isinstance(e,dict) and isinstance(e.get("new_string"),str)]
 return "\n".join(parts)
def secret_kind(s): return next((n for n,p in SECRETS if p.search(s)),None)
