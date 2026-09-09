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

可將 `project` 改為 `local` 或 `user`。Codex／Claude 的 `user` selector 流程都需要
先在對應 scope 註冊本機 marketplace；Claude user scope 會套用到所有 Claude Code
專案。移除所有目前找到的受管模式：

```bash
./scripts/select-claude-mode --remove --scope project .
```

Claude user scope 的 repository selector 流程：

```bash
claude plugin marketplace add "$(pwd)" --scope user
./scripts/select-claude-mode integrated-harness --scope user .
./scripts/verify-claude-mode integrated-harness .
```

若沒有本機 checkout，也可使用 Claude 原生 CLI；這條替代流程不使用本專案的
selector／verifier：

```bash
claude plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --scope user --sparse .claude-plugin claude/plugins
claude plugin install integrated-harness@ai-guardrail-kit --scope user
claude plugin list --json
```

確認 plugin 清單中的 `scope` 為 `user` 且 `enabled` 為 `true`。全域 user scope
不要與 `project`／`local` managed mode 混用；安裝、更新或移除後請開新的 Claude
Code session。

## Codex

Codex 只由 installer 管理全域 `ai-guardrail-loader@ai-guardrail-kit`；mode plugin
不再由 selector add/remove。remote marketplace plugin 自帶 manager、loader、selector
與 verifier，可部署到 `$CODEX_HOME/guardrail/{loader,bin}`，不依賴 checkout。

```bash
codex plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --ref main --sparse .agents --sparse codex/plugins
codex plugin add ai-guardrail-loader@ai-guardrail-kit
# <plugin-directory> 由 codex plugin list --json 查得；只需 bootstrap 一次
<plugin-directory>/hooks/install-codex-guardrail-loader --plugin-root <plugin-directory>
guardrail_bin="${CODEX_HOME:-$HOME/.codex}/guardrail/bin"
"$guardrail_bin/select-codex-mode" harness --scope project --ref vX.Y.Z /path/to/project
"$guardrail_bin/verify-codex-mode" harness --scope project /path/to/project
```

Windows PowerShell 可不經 Git Bash／WSL，直接使用 plugin 附帶的 Python manager 設定全域
`user` fallback。`<plugin-directory>` 由 `codex plugin list --json` 查得：

```powershell
$pluginRoot = '<plugin-directory>'
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$manager = Join-Path $codexHome 'guardrail\bin\codex-runtime-manager.py'

py -3 "$pluginRoot\hooks\manager.py" install-loader --plugin-root "$pluginRoot"
py -3 $manager select integrated-harness --scope user --ref main
py -3 $manager verify integrated-harness --scope user
```

`integrated-harness` 可替換為任一 mode；沒有 `py` launcher 時改用 Python 3.9+ 的 `python`。
`user` 設定只作全域 fallback，`local > project > user > disabled`；切換後開啟新的 Codex thread。
首次安裝或 plugin hook 更新後，在 Codex 輸入 `/hooks` 審閱並信任 loader hook，否則 Codex
會略過未信任的 plugin hook。

上面的 `$CODEX_HOME/guardrail/bin/select-codex-mode` 才是遠端安裝後的實際模式切換入口；
`/path/to/project` 是 `project`／`local` scope 的目標專案，不需要 checkout
`ai-guardrail-kit`。`user` scope 是全域個人 fallback，可省略專案路徑，省略時預設使用目前
目錄作為命令脈絡。若使用本機 checkout 作為 development source，才改用
`./scripts/select-codex-mode` 與 `./scripts/verify-codex-mode`。
實際語法是 `select-codex-mode [--update] <mode> [--scope ...] [--ref ...] [project-dir]`；
移除時使用 `select-codex-mode --remove [--scope ...] [project-dir]`。

Codex 三種 scope 的 selector 如下：`project` 是
`.codex/guardrail/runtime.json`；`local` 是
`.codex/guardrail/runtime.local.json`；`user` 是
`$CODEX_HOME/guardrail/default-runtime.json`。precedence 為
`local > project > user > disabled`。

```bash
"$guardrail_bin/select-codex-mode" harness --scope local --ref vX.Y.Z /path/to/project
"$guardrail_bin/select-codex-mode" integrated-harness --scope user --ref vX.Y.Z
"$guardrail_bin/select-codex-mode" --update harness --scope project --ref vX.Y.Z /path/to/project
"$guardrail_bin/verify-codex-mode" harness --scope project --offline /path/to/project
"$guardrail_bin/verify-codex-mode" integrated-harness --scope user
"$guardrail_bin/select-codex-mode" --remove --scope project /path/to/project
```

`--source github` 只使用核准 HTTPS origin；`local`／`test` 只在明確 development
環境變數下可用。`--offline` 僅使用 runtime index 與完整 cache，不連網。`--update`
才重新取得 manifest；普通重跑保留既有 identity。

`--source github`（預設來源）的全新安裝若未指定 `--ref`，不再靜默信任可變的
`main` 分支：會直接失敗並提示改用 `--ref <commit-or-tag>`（例如上方範例的
`vX.Y.Z`）。僅在明確需要追蹤主幹最新內容的開發／測試情境下，才設定
`AI_GUARDRAIL_ALLOW_MUTABLE_REF=1` 選擇退回舊行為。

Codex 的 shell wrapper 預設依序使用 `python3`、`python`。若 Windows 只有 `py`
launcher 或 Python 不在 PATH，執行命令前設定 `AI_GUARDRAIL_PYTHON`，例如：

```bash
AI_GUARDRAIL_PYTHON=py "$guardrail_bin/select-codex-mode" harness --scope project /path/to/project
```

全域相容 wrapper：

```bash
./scripts/install-codex-global-integrated-harness /path/to/checkout
./scripts/verify-codex-global-integrated-harness /path/to/checkout
./scripts/install-codex-global-integrated-harness --remove /path/to/checkout
```

wrapper 只管理 loader 與 user fallback；不移除 project/local selector、unrelated
plugin、hooks 或個人 orchestration policy。

## 完整解除安裝

### Claude Code marketplace

repository selector 會清除找到的全部受管 mode；完成後驗證並開啟新的 Claude Code
session。若曾以原生 user scope 流程安裝，改以相同 scope 的原生命令移除。

```bash
./scripts/select-claude-mode --remove --scope project /path/to/project
./scripts/verify-claude-mode --no-managed-mode /path/to/project
claude plugin uninstall integrated-harness@ai-guardrail-kit --scope user
claude plugin marketplace remove ai-guardrail-kit
```

### Codex loader 與 runtime

優先使用一鍵指令：預設只列出受管 selector；`--confirm` 才執行解除安裝，
`--prune-cache` 才會刪除未引用 runtime cache。

```bash
guardrail_bin="${CODEX_HOME:-$HOME/.codex}/guardrail/bin"
"$guardrail_bin/uninstall-codex-guardrail"
"$guardrail_bin/uninstall-codex-guardrail" --confirm --prune-cache
```

Windows PowerShell 請直接使用已部署 manager：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$manager = Join-Path $codexHome 'guardrail\bin\codex-runtime-manager.py'
py -3 $manager uninstall
py -3 $manager uninstall --confirm --prune-cache
```

下列手動流程適用於需要逐步處理的情境：

先對每個已設定的 project／local 專案移除 selector，並移除 user fallback。只有沒有任何
selector 引用 loader 時，才可執行 loader 卸載；因此必須在移除 marketplace **之前**保留
`<plugin-directory>`。`--remove` 會移除 loader plugin、受管 hooks 與管理工具，保留 cache
及個人 policy。

```bash
guardrail_bin="${CODEX_HOME:-$HOME/.codex}/guardrail/bin"
"$guardrail_bin/select-codex-mode" --remove --scope project /path/to/project
"$guardrail_bin/select-codex-mode" --remove --scope local /path/to/project
"$guardrail_bin/select-codex-mode" --remove --scope user

# 先以 codex plugin list --json 找出 <plugin-directory>
<plugin-directory>/hooks/install-codex-guardrail-loader --plugin-root <plugin-directory> --remove
codex plugin marketplace remove ai-guardrail-kit
```

若 `--remove` 拒絕執行，代表仍有受管理的 selector；請移除該 selector，勿手動刪除
`selector-index.json` 或 `hooks.json`。需要刪除未引用 runtime cache 時，應在卸載
loader 前先執行上方的 `prune-codex-runtime-cache --apply`。

### copy-in

Claude Code 與 Copilot 的 copy-in 只可逆轉當初已知的複製：從設定中移除本套件新增的
hook entries，再刪除相應 README 所列的檔案；不要刪除可能也含其他設定的 `.claude/`、
`.github/hooks/` 或 settings 檔。完成後重新載入對應 IDE，並以 `/hooks` 確認。

清理未引用 runtime（預設只預覽；`--apply` 才實際刪除）：

```bash
$CODEX_HOME/guardrail/bin/prune-codex-runtime-cache --dry-run --max-age 30
$CODEX_HOME/guardrail/bin/prune-codex-runtime-cache --apply --max-age 30
```

## 更新已安裝的 Codex marketplace／plugin

已用 `marketplace add` 註冊過來源的環境，若要切到另一個 ref（例如新發布的
tag），`marketplace add` 會直接報錯拒絕（`marketplace 'xxx' is already added
from a different source; remove it before adding this source`）；`codex plugin`
也沒有 `update` 子指令。

若已有本機 checkout（例如維護者自己的開發環境），可用下方封裝好的一行指令
（等同下面手動序列的第 1、3、4、5 步；只是既有 `codex` CLI 呼叫的封裝，不引入
新的信任邊界）：

```bash
./scripts/refresh-codex-guardrail-ref vX.Y.Z
```

沒有本機 checkout 時，或需要理解每一步實際做了什麼，才用下面完整的手動序列：

```bash
# 1. 移除舊來源，改註冊到新 ref
codex plugin marketplace remove ai-guardrail-kit
codex plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git \
  --ref vX.Y.Z --sparse .agents --sparse codex/plugins

# 2. 確保 marketplace 快照確實刷新
codex plugin marketplace upgrade ai-guardrail-kit

# 3. 重新安裝 loader plugin（無 update 子指令，remove 後重新 add）
codex plugin remove ai-guardrail-loader@ai-guardrail-kit
codex plugin add ai-guardrail-loader@ai-guardrail-kit

# 4. 查出新的 <plugin-directory>（source.path 欄位）
codex plugin list --json

# 5. 用 --update 重新部署 loader 到 $CODEX_HOME/guardrail/bin
<plugin-directory>/hooks/install-codex-guardrail-loader --plugin-root <plugin-directory> --update

# 6. 用 --update 強制重抓 manifest/archive，釘在新 ref
guardrail_bin="${CODEX_HOME:-$HOME/.codex}/guardrail/bin"
"$guardrail_bin/select-codex-mode" --update <mode> --scope project --ref vX.Y.Z /path/to/project
"$guardrail_bin/verify-codex-mode" <mode> --scope project /path/to/project
```

完成後在 Codex 輸入 `/hooks` 重新信任更新後的 hook，並開新的 Codex thread／session
讓變更生效。

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
