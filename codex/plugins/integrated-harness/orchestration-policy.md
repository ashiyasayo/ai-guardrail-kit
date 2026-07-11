# Codex Guardrail 編排政策

## 核准模式

- 核准模式：strict

支援 `strict`、`standard`、`light`。缺少或無效設定一律採用 strict。

## Strict Bash 測試與建置 Allowlist

- `bash tests/`
- `dotnet test`
- `dotnet build`
- `npm test`
