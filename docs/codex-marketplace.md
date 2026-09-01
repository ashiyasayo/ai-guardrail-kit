# Codex guardrail marketplace

Codex 使用一個全域 `ai-guardrail-loader` plugin；四個 mode 是每個專案的
runtime identity，不是全域 plugin 安裝狀態。Codex 沒有本專案可依賴的 per-project
plugin scope，因此 selector 只寫本專案的 selector 檔。

## Remote/no-checkout bootstrap

在已註冊本 marketplace 的 Codex 使用者環境，安裝唯一 loader：

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
./scripts/select-codex-mode harness --scope project --ref vX.Y.Z /path/to/project
./scripts/select-codex-mode integrated-harness --scope local --ref vX.Y.Z /path/to/project
./scripts/verify-codex-mode harness --scope project /path/to/project
./scripts/select-codex-mode --remove --scope local /path/to/project
```

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
