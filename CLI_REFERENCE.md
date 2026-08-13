# CLI Reference

本專案提供四種互斥模式：`decomposition-gate`、`sensitive-data-guard`、
`harness`、`integrated-harness`。同一平台、同一專案只能啟用一種。

## 互動命令模式

在 Codex 或 Claude Code 的互動輸入列開頭加上 `!`，可直接執行 shell 命令，不必離開
目前的 thread／session 或另外開終端機：

```text
!git status
!python --version
```

命令會在目前工作目錄執行，結束後回到原本的互動對話；實際 shell 語法依作業系統與
平台 CLI 的行為為準。

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

## 釘版本與發版

從 GitHub 註冊 Codex marketplace 時，以 `--ref` 選擇來源快照：

```bash
# 最新主幹
codex plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --ref main --sparse .agents --sparse codex/plugins

# 固定在某個發布版本
codex plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --ref v0.1.0 --sparse .agents --sparse codex/plugins
```

Claude／Copilot 需固定版本時，clone 指定 tag 後 copy-in：

```bash
git clone --depth 1 --branch v0.1.0 https://github.com/ashiyasayo/ai-guardrail-kit.git
```

維護者發版（`main` 受保護，CHANGELOG 定版須走 PR，合併後才打 tag）：

```bash
git switch main && git pull
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z --title "vX.Y.Z" --notes "<該版 CHANGELOG 段落>"
```

版本語意與各平台版號載體差異見 [`VERSIONING.md`](VERSIONING.md)。

## sensitive-data-guard 行為

- 阻擋寫入內容或命令中的明文密碼、API Key、Token 與憑證。
- 阻擋使用者提示詞中的受支援個資。
- 在送出寫入工具前遮罩受支援個資。
- 不提供危險命令封鎖、拆解閘門、人類核准或編排。

## integrated-harness 治理邊界

`integrated-harness` 的治理政策不指定任務分解、模型路由或代理調度方式；平台可自行
決定工作策略，但仍須遵守計畫與核准、外部副作用、敏感資料、成本、驗收及失敗揭露
規則。`harness` 不提供編排功能；其歷史編排提示稿已 deprecated。

Claude 版會在 SessionStart 載入風險分級的執行協定：精簡進度更新、避免無新證據的
重複驗證，並將 subagent 限制於具一定規模且可真正獨立並行的工作。這不會放寬任何
計畫、核准或安全 hook。

Claude `decomposition-gate` 的 copy-in 與 marketplace 版本同樣會在 SessionStart
載入風險分級協定；安裝或更新後必須開啟新 session 才會套用。

完整 marketplace 生命週期與限制請見
[`docs/claude-marketplace.md`](docs/claude-marketplace.md) 與
[`docs/codex-marketplace.md`](docs/codex-marketplace.md)。

## GitHub Copilot (VS Code)（實驗性，Preview）

兩種模式皆採 copy-in（無 marketplace／selector），且**互斥、不得同時安裝**。

`decomposition-gate`：

```bash
mkdir -p your-project/.github/hooks your-project/.github/guardrail/plan
cp copilot/plugins/decomposition-gate/hooks/* your-project/.github/hooks/
cp copilot/plugins/decomposition-gate/plan/decomposition.template.md your-project/.github/guardrail/plan/
```

`sensitive-data-guard`（無拆解產出物，故不需要 guardrail/plan 目錄）：

```bash
mkdir -p your-project/.github/hooks
cp copilot/plugins/sensitive-data-guard/hooks/* your-project/.github/hooks/
```

維護者同步 Copilot 的共用 hook 來源（`shared/copilot/`）：

```bash
scripts/sync-copilot-hook-copies            # 套用
scripts/sync-copilot-hook-copies --check    # 驗證無漂移
```

VS Code 使用者設定需含 `"chat.useCustomAgentHooks": true` 與
`"chat.hookFilesLocations": { ".github/hooks": true }`，改後 Reload Window。
若 Windows 探測不到 python，設定環境變數 `GUARDRAIL_PYTHON` 指向直譯器完整路徑。
僅 Copilot Agent mode 生效；行為與限制見
[`copilot/plugins/decomposition-gate/README.md`](copilot/plugins/decomposition-gate/README.md)。
