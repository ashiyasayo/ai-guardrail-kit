# Codex guardrail marketplace

Codex 使用一個全域 `ai-guardrail-loader` plugin；四個 mode 是每個專案的
runtime identity，不是全域 plugin 安裝狀態。Codex 沒有本專案可依賴的 per-project
plugin scope，因此 selector 只寫本專案的 selector 檔。

## Remote/no-checkout bootstrap

若尚未註冊 marketplace，先執行：

```bash
codex plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --ref main --sparse .agents --sparse codex/plugins
```

接著在已註冊本 marketplace 的 Codex 使用者環境，安裝唯一 loader：

```bash
codex plugin add ai-guardrail-loader@ai-guardrail-kit
```

`ai-guardrail-loader` plugin 自帶 `hooks/manager.py`、loader、selector 與 verifier
bootstrap。依 Codex `plugin list --json` 顯示的已安裝 plugin directory，執行：

```bash
<plugin-directory>/hooks/install-codex-guardrail-loader --plugin-root <plugin-directory>
```

它會把 loader、manager 與 selector/verifier 入口部署到
`$CODEX_HOME/guardrail/{loader,bin}/`；已選專案只執行 cache 內的 verified payload，
不依賴 checkout 絕對路徑。loader installer 是唯一可以管理
`ai-guardrail-loader@ai-guardrail-kit` 的本專案流程；selector 不呼叫任何 mode
plugin add/remove。

有 checkout 時可使用等效入口：

```bash
./scripts/install-codex-guardrail-loader --repo .
```

上述 shell entrypoint 預設依序探測 `python3`、`python`。若環境只有 Windows `py`
launcher 或 Python 不在 PATH，請在執行 bootstrap、selector、verifier 或 prune 前設定
`AI_GUARDRAIL_PYTHON`；這只影響管理命令，不會讓 hook 熱路徑連網。

### Windows PowerShell：設定全域 fallback

PowerShell 不會直接執行無副檔名的 Bash entrypoint。若不使用 Git Bash 或 WSL，可直接呼叫
plugin 內附的 Python manager。以下 `<plugin-directory>` 應替換為 `codex plugin list --json`
顯示的已安裝 plugin 目錄：

```powershell
$pluginRoot = '<plugin-directory>'
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$manager = Join-Path $codexHome 'guardrail\bin\codex-runtime-manager.py'

# 只需執行一次：部署穩定 loader 與管理入口
py -3 "$pluginRoot\hooks\manager.py" install-loader --plugin-root "$pluginRoot"

# 為所有未設定 project/local selector 的專案建立全域 fallback
py -3 $manager select integrated-harness --scope user --ref main
py -3 $manager verify integrated-harness --scope user
```

若沒有 `py` launcher，改用 Python 3.9+ 的 `python`。`integrated-harness` 可替換成
`decomposition-gate`、`sensitive-data-guard` 或 `harness`。選擇或變更模式後，請開啟新的
Codex thread；`user` 只作 fallback，`local > project > user > disabled` 仍決定實際生效模式。
首次安裝或 plugin hook 更新後，請在 Codex 輸入 `/hooks` 審閱並信任
`ai-guardrail-loader` 的 hook；Codex 會略過未信任的 plugin hook。

在 Windows，installer 會將 hook 寫成 PowerShell 的 `$env:...; & <python>` 形式；其行為與
POSIX／Claude 的「先設定 Loader 環境變數，再啟動 Python」相同，但不混用 Bash 語法。若
`$CODEX_HOME/hooks.json` 記錄的 Python 已移除或變更，先安裝可用的原生 Python 3.9+，再重跑
上述 `install-loader` 指令以重新產生 hook；不要以 WSL 的 Python 路徑安裝 Windows Codex hook。

## Selecting a runtime

四個 mode：`decomposition-gate`、`sensitive-data-guard`、`harness`、
`integrated-harness`。selector 位置如下：

| Scope | Selector |
| --- | --- |
| project | `<project>/.codex/guardrail/runtime.json` |
| local | `<project>/.codex/guardrail/runtime.local.json` |
| user | `$CODEX_HOME/guardrail/default-runtime.json` |

precedence 固定為 `local > project > user > disabled`。

```bash
guardrail_bin="${CODEX_HOME:-$HOME/.codex}/guardrail/bin"
"$guardrail_bin/select-codex-mode" harness --scope project --ref vX.Y.Z /path/to/project
"$guardrail_bin/select-codex-mode" integrated-harness --scope local --ref vX.Y.Z /path/to/project
"$guardrail_bin/select-codex-mode" integrated-harness --scope user --ref vX.Y.Z
"$guardrail_bin/verify-codex-mode" harness --scope project /path/to/project
"$guardrail_bin/verify-codex-mode" integrated-harness --scope user
"$guardrail_bin/select-codex-mode" --remove --scope local /path/to/project
```

以上是遠端 marketplace bootstrap 完成後的實際切換指令；`/path/to/project` 是
`project`／`local` scope 的目標專案，不需要把 `ai-guardrail-kit` clone 下來。`user` scope
是全域個人 fallback，可省略 `project-dir`，省略時預設使用目前目錄。若使用 checkout 作為
本機 development source，
才使用 `./scripts/select-codex-mode`、`./scripts/verify-codex-mode` 等等效入口。
實際語法是 `select-codex-mode [--update] <mode> [--scope ...] [--ref ...] [project-dir]`；
移除時使用 `select-codex-mode --remove [--scope ...] [project-dir]`。

`--update` 才會重新解析 manifest；普通重跑保留既有 identity。正式來源只接受
`github` alias 與核准 HTTPS origin。`local`／`test` 必須明確設定
`AI_GUARDRAIL_ALLOW_DEVELOPMENT_SOURCE=1`、manifest path 與 archive directory。
`--offline` 僅使用 `$CODEX_HOME/guardrail/runtime-index.json` 中唯一匹配的 identity，
不呼叫 network adapter。

manifest 會固定 `ref`、40-hex `commit`、runtime version、archive size、SHA-256 及
entrypoints。archive 先驗 hash，再檢查 UTF-8 相對 POSIX regular files、拒絕
symlink、hardlink、device、FIFO、duplicate normalized path、path traversal 與解壓大小
上限，最後才 atomic publish 到 `runtime-cache/sha256/<digest>/`。

## Loader hooks and safety

loader 從 Codex event 的 `cwd` 找最近含 selector 的 project root，依 precedence
解析 runtime。它不連網、不更新 cache、不執行 URL 或 selector 提供的 command。
每次執行前重新確認 cache metadata、payload 全檔 digest、entrypoint regular file
與 containment，子程序固定使用 `[python, "--", verified_entrypoint]`、`shell=False`，
原始 event bytes 送入 stdin。

註冊的 event slots 保留既有順序與語意：

- `PreToolUse exec_command|apply_patch`：decomposition、plan、security
- `PreToolUse apply_patch`：獨立 PII updatedInput
- `UserPromptSubmit`：PII prompt deny
- `SessionStart startup|resume|clear|compact`：integrated-harness reminder

安全事件 runtime 缺失或驗證失敗時 fail closed；SessionStart 輸出明確診斷。環境會
移除 token、password、secret、auth、cookie、proxy 等敏感變數，且不記錄 event、prompt
或 tool input。

## Global integrated-harness compatibility wrapper

```bash
./scripts/install-codex-global-integrated-harness /path/to/checkout
./scripts/verify-codex-global-integrated-harness /path/to/checkout
./scripts/install-codex-global-integrated-harness --remove /path/to/checkout
```

此 wrapper 只確保 loader、`integrated-harness` user fallback 與既有個人政策建立來源；
不安裝或移除 integrated-harness mode plugin。`--remove` 不刪除個人
`orchestration-policy.md`，也不影響 project/local selector 或 unrelated hooks/plugins。

## Migration and rollback

selector 會辨識舊 TOML marker、local/user hook marker 與 legacy global marker。只有
完整且一致的舊 hook 集合才會遷移；混合、缺漏或無法判定 mode 回報
`E_LEGACY_AMBIGUOUS` 並保持 bytes 不變。selector、runtime index 與 loader pointer
使用同目錄 temporary file、flush/fsync（平台可行時）及 `os.replace`；manifest、download、
archive、cache publish 或 post-verify 失敗會保留舊 selector 可用。非受管 hooks、plugins
與個人 policy 永遠保留。

## Runtime cache cleanup

selector 會在 `$CODEX_HOME/guardrail/selector-index.json` 登記受管 selector 路徑，供
低頻清理流程建立引用集合。清理預設為 dry-run；只有明確 `--apply` 才會刪除超過
保留天數、未被任何已登記 selector 引用且重新驗證完整的 digest cache：

```bash
$CODEX_HOME/guardrail/bin/prune-codex-runtime-cache --dry-run --max-age 30
$CODEX_HOME/guardrail/bin/prune-codex-runtime-cache --apply --max-age 30
```

selector registry 損壞、cache 正在被 lock、候選內容不完整或是 symlink 時，清理會
停止或跳過該項，不會遞迴刪除來源不明的路徑。hook 熱路徑不執行 prune。

## Troubleshooting and tests

穩定錯誤碼包括 `E_NETWORK`、`E_SOURCE_DENIED`、`E_MANIFEST_INVALID`、
`E_DIGEST_MISMATCH`、`E_ARCHIVE_UNSAFE`、`E_CACHE_CORRUPT`、`E_RUNTIME_MISSING`、
`E_HOOK_FAILED` 與 `E_ROLLBACK_FAILED`。完整測試需 Python 3.9+、Bash、fake Codex；
測試使用 in-memory／temporary filesystem／fake process，不依賴真實網路。
