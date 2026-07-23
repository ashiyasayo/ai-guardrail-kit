# CLI Reference

本專案提供四種互斥模式：`decomposition-gate`、`sensitive-data-guard`、
`harness`、`integrated-harness`。同一平台、同一專案只能啟用一種。

## Claude Code

```bash
claude plugin marketplace add "$(pwd)" --scope project
./scripts/select-claude-mode sensitive-data-guard --scope project .
./scripts/verify-claude-mode sensitive-data-guard .
```

可將 `project` 改為 `local`。移除目前受管模式：

```bash
./scripts/select-claude-mode --remove --scope project .
```

## Codex

```bash
codex plugin marketplace add "$(pwd)"
./scripts/select-codex-mode sensitive-data-guard .
./scripts/verify-codex-mode sensitive-data-guard .
```

移除目前受管模式：

```bash
./scripts/select-codex-mode --remove /path/to/project
./scripts/verify-codex-mode --no-managed-mode /path/to/project
```

## sensitive-data-guard 行為

- 阻擋寫入內容或命令中的明文密碼、API Key、Token 與憑證。
- 阻擋使用者提示詞中的受支援個資。
- 在送出寫入工具前遮罩受支援個資。
- 不提供危險命令封鎖、拆解閘門、人類核准或編排。

## integrated-harness 治理邊界

`integrated-harness` 的治理政策不指定任務分解、模型路由或代理調度方式；平台可自行
決定工作策略，但仍須遵守計畫與核准、外部副作用、敏感資料、成本、驗收及失敗揭露
規則。`harness` 不提供編排功能；其歷史編排提示稿已 deprecated。

完整 marketplace 生命週期與限制請見
[`docs/claude-marketplace.md`](docs/claude-marketplace.md) 與
[`docs/codex-marketplace.md`](docs/codex-marketplace.md)。
