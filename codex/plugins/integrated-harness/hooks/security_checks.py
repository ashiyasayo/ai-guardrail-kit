import re
D=(("遞迴強制刪除",re.compile(r"\brm\b(?=[^;&|]*\s(?:-[A-Za-z]*r[A-Za-z]*|--recursive))(?=[^;&|]*\s(?:-[A-Za-z]*f[A-Za-z]*|--force))")),("硬重置",re.compile(r"\bgit\s+reset\s+--hard\b")),("資料庫毀滅性操作",re.compile(r"(?i)\b(?:DROP\s+(?:TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)\b")))
S=(("AWS Access Key",re.compile(r"AKIA[0-9A-Z]{16}")),("私鑰區塊",re.compile(r"-----BEGIN\s+(?:RSA|EC|OPENSSH|DSA|PGP)?\s*PRIVATE KEY-----")),("一般憑證指派",re.compile(r"(?i)\b(?:password|secret|api[_-]?key|access[_-]?token)\b\s*[:=]\s*['\"][^'\"\s]{8,}['\"]")))
def dangerous_command(x):return next((n for n,p in D if isinstance(x,str) and p.search(x)),None)
def pending_content(i):return "\n".join(i[k] for k in ("content","new_string","new_source","command") if isinstance(i.get(k),str)) if isinstance(i,dict) else ""
def secret_kind(x):return next((n for n,p in S if p.search(x)),None)
