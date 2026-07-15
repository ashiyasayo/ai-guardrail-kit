# Codex Guardrail 編排政策

設定方式與各模式的完整行為，請見同目錄的 [README.md](README.md)。

## 核准模式

- 核准模式：strict

支援 `strict`、`standard`、`light`。缺少或無效設定一律採用 strict。

## Strict Bash 測試與建置 Allowlist

- `bash tests/`
- `dotnet test`
- `dotnet build`
- `npm test`
