# Codex Guardrail 編排政策

設定方式與各模式的完整行為，請見同目錄的 [README.md](README.md)。

## 核准模式

- Approval Mode: strict

支援 `strict`、`standard`、`light`。缺少或無效設定一律採用 strict。

- `strict`：計畫與允許修改範圍通過後，測試／建置命令還須符合下方 allowlist；每個
  `apply_patch` 或可變更狀態的命令均需一次性人工操作收據。
- `standard`：保留計畫與允許修改範圍，免人工操作收據，也不套用 strict 測試／建置
  allowlist。
- `light`：只要求包含必要標記的基本拆解，免允許修改範圍與人工操作收據；只提供思考
  紀律，不提供授權控制。

經窄化解析的唯讀探索命令（例如 `rg`、`cat`、`git status`）可在計畫建立前執行，且不消耗
操作收據。含 shell operator、輸出寫入旗標或可執行 helper 的命令不屬於唯讀快速通道。

## Strict Bash 測試與建置 Allowlist

- `bash tests/`
- `dotnet test`
- `dotnet build`
- `npm test`
- `npm run build`
