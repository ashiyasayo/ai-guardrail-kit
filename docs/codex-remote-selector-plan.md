# Codex 遠端 selector 與每專案 runtime 規格

狀態：第一階段實作契約（交付 luna）
範圍：僅 Codex 的 selector、loader、runtime 發佈與相容遷移
決策：採用「全域單一穩定 loader + 每專案模式描述檔 + SHA-256 驗證的內容定址 runtime cache」；模式切換不得再安裝或移除全域模式 plugin。

## 1. 現況與限制

目前 `scripts/select-codex-mode` 從腳本所在目錄推導 ai-guardrail-kit checkout，透過使用者層級的 `codex plugin add/remove` 維持「全域只安裝一種受管模式」，再把 checkout 內 `codex/plugins/<mode>/hooks` 的絕對路徑寫入：

- `project`：`<project>/.codex/config.toml`
- `local`：`<project>/.codex/hooks.json`
- `user`：`$CODEX_HOME/hooks.json`

四個 Codex plugin 的 manifest 只宣告 skills；hook 接線由 selector 手動產生。`integrated-harness` 另在不存在時建立 `$CODEX_HOME/guardrail/orchestration-policy.md`，且不覆寫既有個人政策。現有 global installer 也會安裝 `integrated-harness` plugin，並將 checkout 內 hook 的絕對路徑寫入 user hooks。

因此現況有下列限制：

1. Codex plugin 安裝狀態是使用者層級；專案 A 切換模式會移除專案 B 所依賴的全域模式 plugin。
2. hook 命令綁定執行 selector 的 checkout 絕對路徑；checkout 移動、刪除或停在舊版後，既有專案可能失效或執行舊程式。
3. `--update` 更新 marketplace 與全域 plugin 快照，無法對單一專案獨立釘版、更新或 rollback。
4. 現有 fake Codex 以單一全域 `installed` 檔模擬 plugin，測試模型本身也強化了錯誤的全域互斥假設。
5. 官方文件雖說 plugin 可包含 skills/hooks 並可由 marketplace 發佈，但本專案沒有可依賴的 per-project plugin 安裝契約；本方案不得假設 Codex 日後或目前提供該 scope。

## 2. 目標與非目標

### 2.1 目標

- 使用者全域只安裝一個穩定的 `ai-guardrail-loader` plugin／loader；四種模式不再成為全域安裝狀態。
- 專案 A 與 B 可在同一使用者、同一時間分別使用不同模式與不同 runtime 版本。
- selector 可從 GitHub HTTPS 遠端 manifest 取得模式 runtime，驗證 SHA-256 後放入使用者 cache；hook 永遠只執行已驗證 cache 內容。
- 支援釘版本／來源、明確更新、離線使用既有 cache、原子模式切換、失敗 rollback、舊格式偵測與遷移。
- checkout 只提供管理 CLI 與可選的本機開發來源，不再是已選模式的執行期依賴。
- 保留現有四模式的 hook 事件、matcher、執行順序、決策語意與個人政策不覆寫原則。

### 2.2 非目標

- 不修改 Claude 或 Copilot 的安裝、selector、hook 或 runtime。
- 不把四種產品模式合併成 feature flags；模式仍為互斥產品邊界。
- 不建立、宣稱或依賴官方不存在的 Codex per-project plugin scope。
- 不在 hook 熱路徑自動連網、更新、安裝 plugin 或修改專案設定。
- 不提供任意 URL 執行器、套件簽章基礎設施、背景更新 daemon 或跨使用者系統服務。
- 不自動刪除使用者自訂的 orchestration policy、非本工具 hooks 或未知 cache。

## 3. 選定方案

### 3.1 穩定 loader

新增 marketplace plugin `ai-guardrail-loader`，它是唯一允許由本專案全域 `codex plugin add/remove` 管理的 Codex plugin。安裝器將其薄啟動器部署到：

```text
$CODEX_HOME/guardrail/loader/releases/<loader-version>/
$CODEX_HOME/guardrail/loader/current.json
```

`current.json` 是由安裝器原子替換的 pointer，不使用 symlink。`$CODEX_HOME/hooks.json` 中的受管 hook 命令只指向 loader 的穩定入口，不含 checkout 或 mode runtime 路徑。loader 必須註冊四模式聯集事件，但每次依有效模式只 dispatch 該模式的規格：

- `PreToolUse`：matcher `exec_command|apply_patch`
- `PreToolUse`：matcher `apply_patch`
- `UserPromptSubmit`
- `SessionStart`：matcher `startup|resume|clear|compact`

未被有效模式使用的事件必須無輸出成功返回。loader plugin 的 skill 只說明管理方式，不得自行決定專案模式。

安裝 loader 與選擇專案模式是兩個交易：

- `install-codex-guardrail-loader`：低頻、使用者層級，管理單一 loader plugin、穩定 hook 接線與 loader 版本。
- `select-codex-mode`：高頻、專案／設定層級，只管理 runtime cache 與 selector 設定，禁止呼叫 `codex plugin add/remove`。

### 3.2 runtime 發佈單位與 manifest

每個 repo tag 發佈一份受版本控制的 runtime manifest。repo tag 仍是 `VERSIONING.md` 定義的唯一發布座標；manifest 的 `runtime_version` 是該 tag／commit 的不可變來源識別，不是新產品版號或 per-plugin SemVer。

建議遠端入口：

```text
https://raw.githubusercontent.com/ashiyasayo/ai-guardrail-kit/<ref>/codex/runtime-manifest.json
```

manifest schema v1 必須包含：

```json
{
  "schema_version": 1,
  "release": {
    "source": "https://github.com/ashiyasayo/ai-guardrail-kit",
    "ref": "vX.Y.Z",
    "commit": "40-hex-commit",
    "runtime_version": "vX.Y.Z+<short-commit>"
  },
  "modes": {
    "harness": {
      "archive_url": "https://.../harness.tar.gz",
      "archive_sha256": "64-lower-hex",
      "archive_size": 12345,
      "entrypoints": {
        "pretool.security": "hooks/security_guard.py",
        "pretool.plan": "hooks/plan_gate.py",
        "pretool.pii": "hooks/pii_guard.py",
        "prompt.pii": "hooks/pii_guard.py"
      }
    }
  }
}
```

契約：

- `schema_version`、mode、entrypoint key、URL scheme、SHA-256、大小上限及 commit 格式採 allowlist 驗證；未知必要欄位或 schema 版本直接拒絕。
- 正式遠端來源只允許預先核准的 HTTPS origin；redirect 每一跳也要重新驗證 scheme／host，限制跳數、下載大小與 timeout。
- archive 只能含 UTF-8、相對 POSIX 路徑的 regular files；拒絕絕對路徑、`..`、空段、Windows drive/UNC、NUL、symlink、hardlink、device、FIFO 及重複正規化路徑。
- 先驗證 archive 位元組 SHA-256，再解壓到同一 cache volume 的 staging；解壓後驗證 entrypoint 為 staging 內 regular file，且不可經 symlink 逸出。
- runtime 不得從 manifest 接受 shell command；entrypoint 僅為相對檔案路徑，執行命令由本地 loader 固定組成。
- 正式 tag 的 manifest 與 archive 必須不可變；`main` 可供明確要求最新者使用，但 selector 解析後必須把 commit 與 SHA-256 固化進專案設定。

### 3.3 cache、安裝與更新

cache 位置：

```text
$CODEX_HOME/guardrail/runtime-cache/sha256/<archive-sha256>/
  runtime.json
  payload/
$CODEX_HOME/guardrail/downloads/
$CODEX_HOME/guardrail/locks/
```

`runtime.json` 記錄 schema、mode、source、ref、commit、runtime version、archive SHA-256、entrypoints 與安裝完成標記。目錄名稱以已驗證 archive digest 定址；同一內容跨專案重用，不存在「目前全域模式」。

安裝／更新交易：

1. 解析 selector 參數與目標 scope，不先修改現行設定。
2. 取得 manifest；`--offline` 禁止任何網路 adapter 呼叫。
3. 驗證 manifest，解析成完整不可變 runtime identity。
4. 若 digest cache 已存在，重新驗證 `runtime.json` 與必要 entrypoint；若損壞則隔離並報錯，不執行。
5. 若 cache 不存在，下載到隨機 staging，驗證 digest、大小、archive 路徑與 entrypoint，再以同 volume rename 發佈內容定址目錄；並行程序以每 digest lock 協調。
6. 產生新的 scope selector 檔到同目錄 temporary file，flush／fsync（平台可行時）後 `os.replace` 原子提交。
7. 提交後透過 loader 的 `verify` interface 做一次解析與 dispatch dry-run；失敗則以交易前 bytes／mode 還原 selector 檔，cache 可保留為未引用內容。

`--update` 只更新指定 scope／專案的 runtime identity。manifest 下載、驗證、cache 安裝或 post-verify 任一步失敗，原 selector 與舊 cache 都保持可用；不得像現況同模式 refresh 一樣失去舊內容 bytes。rollback 不需要重新下載。

離線規則：

- 已釘 digest 且 cache 完整：正常執行。
- `select --offline` 指定的 ref 可由本機可信索引唯一解析到 cache：可切換。
- ref 未在本機索引或 cache 不完整：明確失敗，不改設定、不降級到任意舊版本。
- hook 熱路徑永遠等同 offline；找不到或驗證失敗時，安全事件 fail closed，`SessionStart` 回傳明確診斷提醒，不連網修復。

### 3.4 scope 與有效模式

新 selector 檔：

| scope | 位置 | 用途 |
| --- | --- | --- |
| `project` | `<project>/.codex/guardrail/runtime.json` | 可提交、團隊共享的專案選擇 |
| `local` | `<project>/.codex/guardrail/runtime.local.json` | 本機覆寫；應提示加入 ignore，不自動修改 `.gitignore` |
| `user` | `$CODEX_HOME/guardrail/default-runtime.json` | 無專案／本機選擇時的 fallback |

selector 檔只保存：schema、scope、mode、完整 source/ref/commit/runtime version、archive SHA-256 與必要相容欄位；不得保存 token、cookie、Authorization header 或任意命令。

有效模式 precedence 固定為：

```text
local > project > user > disabled
```

`--remove --scope <scope>` 只移除該層受管 selector，不影響其他層、loader plugin、runtime cache 或其他專案。故 A 的 project selector 可釘 `harness@shaA`，B 可同時釘 `integrated-harness@shaB`；切換 A 不修改 B、user hooks 或任何全域 mode plugin。

`user` 是 fallback，不是覆蓋所有專案的強制政策。需要強制組織政策不在本階段範圍。

## 4. 深 module、interface 與 seam

建立單一深 module `codex-runtime-manager`，由 selector、verifier、loader 與 global installer 共用。它把來源解析、cache 安裝、scope precedence、安全驗證、交易與 dispatch 複雜度收在小 interface 後面。

### 4.1 外部 interface

```text
resolve(event, environment) -> EffectiveRuntime | Disabled | Diagnostic
prepare(request) -> PreparedSelection
commit(prepared) -> SelectionResult
verify(target) -> VerificationResult
dispatch(event) -> HookResult
prune(policy) -> PruneResult
```

interface invariants：

- `prepare` 無持久設定副作用；只可建立 staging／cache 候選。
- `commit` 是唯一可改 selector pointer 的操作，且可還原交易前 bytes。
- `resolve`／`dispatch` 不連網、不更新、不安裝、不清理。
- `dispatch` 只接收 `resolve` 回傳且 digest／entrypoint 已驗證的 runtime。
- 錯誤結果包含穩定 error code 與去敏訊息，不把原始事件、提示、tool input 或憑證寫入 log。

### 4.2 seam 與 adapters

只在確實有 production/test 兩種實作處建立內部 seam：

| seam | production adapter | test adapter |
| --- | --- | --- |
| `ManifestSource` | 限制 origin／redirect／timeout／size 的 HTTPS downloader；可選明確的本機開發來源 | in-memory manifest/archive、斷線、截斷、redirect、hash mismatch fake |
| `RuntimeStore` | `$CODEX_HOME` 下 real filesystem、locks、staging、atomic replace | temporary filesystem，支援注入 rename/fsync/lock 失敗 |
| `Clock` | monotonic/system clock | fixed clock，測 lock timeout 與清理年齡 |
| `HookProcess` | 固定 Python 3.9+ argv、stdin/stdout/timeout、無 shell | recording/failing adapter，驗證 entrypoint、事件順序與輸出 |

設定解析、precedence、manifest schema、path containment 與 digest 計算是 module 內部 implementation，不為測試暴露額外 interface。測試與正式 caller 都經同一外部 interface。

## 5. loader 專案 root、模式解析與執行契約

每次 Codex hook 事件由 loader 完整讀取 stdin，先限制輸入大小，再解析 JSON。`cwd` 是找 root 的唯一主要事件欄位；不得從未受信任的 `tool_input`、transcript 內容或環境變數接受 root。

root 演算法：

1. `Path(cwd).resolve(strict=True)` 必須為現存目錄；保留 canonical 路徑。
2. 從 canonical cwd 向父層走訪，第一個含 `.codex/guardrail/runtime.local.json` 或 `.codex/guardrail/runtime.json` 的目錄就是 root；最近的 selector 明確勝出，避免 monorepo 子專案被父層吃掉。
3. 若沒有 selector 而需套用 user fallback，採最近的 `.git` directory/file 或 `.codex` real directory 為 root；仍找不到則以 canonical cwd 為 root。
4. 走訪設固定深度／到 filesystem root 即止；拒絕 selector、`.codex`、`.codex/guardrail` 或 cache 關鍵路徑本身為 symlink。
5. 解析 local、project、user selector，依固定 precedence 得到完整 runtime identity；mode 必須在四模式 allowlist。

dispatch 契約：

- 以 manifest 中的事件對照選擇 entrypoint，但 argv 固定為 `[python, "--", verified_entrypoint]`，`shell=False`；原事件 bytes 原封不動送給 runtime stdin。
- entrypoint 每次執行前以 no-follow／regular-file／containment 檢查，並核對 `runtime.json`；禁止直接執行 URL、manifest command、checkout 路徑或 selector 提供的任意 path。
- 保留現有模式 hook 順序：純 deny 安全檢查先於 plan/ask，PII updatedInput 維持獨立 hook，不把 ask 與 updatedInput 合併到同一程序。
- 限制子程序 timeout、stdout/stderr 大小與可繼承環境。只傳必要的 `AI_GUARDRAIL_*` 狀態與既有 Codex event；移除下載憑證及 selector 內部環境變數。
- loader 自身／runtime 啟動、驗證或逾時錯誤，對 `PreToolUse` 與 `UserPromptSubmit` 採可恢復的 fail closed；不得因例外無輸出而默認放行。診斷不得包含 prompt、patch、command 或秘密內容。

## 6. 相容與遷移

### 6.1 舊 checkout 與絕對 hook 路徑

首次安裝 loader 或首次對 scope 執行新 selector 時，必須辨識現有 managed markers：

- TOML `# ai-guardrail-kit:begin/end`
- `AI_GUARDRAIL_LOCAL_DEFAULT=1`
- `AI_GUARDRAIL_USER_DEFAULT=1`
- `AI_GUARDRAIL_GLOBAL_DEFAULT=1`

遷移順序為：snapshot 舊設定 → 安裝／驗證 loader 與目標 runtime → 寫入新 selector → 將舊 managed hook entry 替換為唯一 loader entry → 驗證 → commit。任一步失敗都恢復舊設定 bytes、mode 與 permissions。只移除能精確辨識為本工具管理的舊 entry；不以路徑片段模糊刪除其他 hooks。

舊 selector 檔不存在但 hook 指向 `repo/codex/plugins/<mode>/hooks/...` 時，可從完整、彼此一致的舊 hook 集推導 mode；若缺漏、混合多模式或 checkout 已不存在，回報 `E_LEGACY_AMBIGUOUS`，要求使用者明確指定 mode，不猜測。

新 loader 成功接管後，checkout 可移動或刪除；新 selector／hook 不得留下 checkout 絕對路徑。尚未遷移的舊設定維持舊行為，不靜默部分轉換。

### 6.2 global installer

`install-codex-global-integrated-harness` 保留命令名稱作相容 wrapper，但新版語意改為：

- 確保單一 loader 已安裝；
- 將 `integrated-harness` 設為 `user` fallback selector；
- 遷移並移除舊 `AI_GUARDRAIL_GLOBAL_DEFAULT=1` hook entries；
- 不安裝或移除 `integrated-harness` mode plugin，不拆除其他專案 runtime。

`--remove` 只移除由此 wrapper 建立的 user fallback 與 legacy global entries；若 loader 仍被 project/local selector 使用，不卸載 loader。若要卸載 loader，必須使用獨立命令，先掃描引用並在仍有引用時拒絕或要求明確 `--force`；本階段不得由 mode remove 隱含觸發。

`$CODEX_HOME/guardrail/orchestration-policy.md` 繼續採「不存在才建立、既有不覆寫、移除不刪除」。runtime 內 bundled policy 可作建立來源，但建立前也要驗證其位於 cache runtime 且屬已驗證 archive。

### 6.3 舊 plugin 安裝狀態

遷移完成後可提示移除四個 legacy mode plugins，但不得在單一專案切換時逐一 add/remove。由 loader installer 的顯式 `migrate`／`uninstall-legacy-plugins` 交易處理；先證明所有受管 hooks 已由 loader 接管，失敗時不得影響 selector。非本 marketplace plugin 永遠不動。

## 7. CLI 契約

保留主要命令名稱，調整為：

```text
select-codex-mode <mode> [--scope project|local|user] [--ref <tag|commit|main>]
                  [--source <approved-source>] [--offline] [project-dir]
select-codex-mode --update <mode> [同上]
select-codex-mode --remove [--scope ...] [project-dir]
verify-codex-mode [expected-mode|--no-managed-mode] [--scope ...] [project-dir]
install-codex-guardrail-loader [--update|--remove|--migrate] [--ref <ref>]
install-codex-global-integrated-harness [--remove] [repo-dir]
verify-codex-global-integrated-harness [--no-installed] [repo-dir]
prune-codex-runtime-cache [--dry-run] [--max-age <days>]
```

語意補充：

- 未給 `--ref` 的首次選擇採文件定義的預設穩定 ref；已選模式的普通重跑保持已釘 identity，只有 `--update` 才解析較新 manifest。
- `--source` 只接受設定檔中的來源別名；正式模式不接受任意 URL。測試／maintainer 本機開發來源須用明確環境隔離開關，產出的 selector 標記 `development`，不得誤稱遠端已驗證版本。
- 成功輸出 mode、scope、project root、ref、commit、SHA-256 前 12 碼、是否 cache hit；不輸出完整本機 cache path 或敏感 header。
- 參數錯誤 exit 2；網路／manifest／digest／cache／交易／legacy ambiguity 使用不同穩定 error code，程序 exit 1；rollback 失敗另用最高嚴重度訊息，不宣稱成功。

建議穩定錯誤碼：`E_USAGE`、`E_NETWORK`、`E_MANIFEST_INVALID`、`E_SOURCE_DENIED`、`E_DIGEST_MISMATCH`、`E_ARCHIVE_UNSAFE`、`E_CACHE_CORRUPT`、`E_SCOPE_UNSAFE`、`E_RUNTIME_MISSING`、`E_HOOK_FAILED`、`E_LEGACY_AMBIGUOUS`、`E_ROLLBACK_FAILED`。

## 8. 安全、錯誤、效能與清理

### 8.1 filesystem 與競態

- 所有可寫 parent 必須是 real writable directory；selector、manifest index、pointer、cache metadata、policy 與 hooks 檔拒絕 symlink／non-regular file。
- 路徑 containment 一律在 canonical path 上比較，不用字串 prefix；Windows 比較須正規化 drive 與大小寫語意。
- 對既有外部檔案無法完全消除 validate-to-open TOCTOU；implementation 應優先使用 no-follow handle、同 directory temporary file、handle-based stat 與 atomic replace，並在文件揭露剩餘平台限制。
- cache 發佈採內容定址且不原地修改；同 digest 只有 complete marker 後才可見。partial staging 在 crash 後可安全清理。
- Windows/Git Bash 不依賴 symlink、POSIX signal 或單一 `python3` 名稱；沿用實際啟動驗證的 Python 3.9+ 探測，路徑含空白、引號與 shell metacharacter 仍以 argv 執行。

### 8.2 敏感資料與網路

- 遠端下載不得接收或記錄 hook event。下載 log 只含來源別名、ref、HTTP status、byte count 與 digest。
- Authorization、proxy credential、cookie、query secret 不寫入 selector、manifest cache、錯誤訊息或測試 snapshot。
- 正式來源原則上使用公開 HTTPS，不在 CLI 接受明文 token；若未來支援私有來源，另立 credential adapter 與 redaction 規格，不在本階段偷渡。
- TLS 驗證不得關閉；禁止 `curl | shell`、直接 import 遠端 Python 或下載後未驗證即執行。

### 8.3 效能

- hook 熱路徑不得掃描整個 cache、呼叫 git/Codex CLI 或網路；最多向上走訪 ancestors、讀三份小 selector/metadata，並啟動該事件所需既有 runtime hooks。
- 可在 loader process 內對同一次事件共用 root／selector／metadata 解析，但不得把有安全語意差異的 hook 合併。
- cache hit 的 selector 不重新下載 archive；只驗證小 metadata 與必要檔案。完整 archive digest 在安裝、verify `--deep` 或損壞疑慮時執行。
- 測試不得用固定 sleep 模擬競態，使用 ready marker／可控 adapter。

### 8.4 清理

- `prune` 預設 dry-run；只刪除未被 project/local/user selector、loader current/rollback pointer 或進行中 lock 引用的完整 cache。
- 先建立引用集合，再逐一於刪除前重新驗證 identity；鎖競爭時跳過，不阻塞 hook。
- 預設保留目前與上一個 loader release、所有被引用 runtime、最近成功 rollback runtime，以及指定 grace period 內未引用 cache。
- 不遞迴刪除來源不明路徑；所有刪除 target 必須解析在 `$CODEX_HOME/guardrail/runtime-cache/sha256/` 的單一 digest child 內。

## 9. 平台 × 模式 × 發佈型態影響矩陣

| 平台 | 模式 | 發佈型態 | 本案處置 | 原因 |
| --- | --- | --- | --- | --- |
| Codex | 四模式 | marketplace mode plugins | 修改：保留模式內容作 runtime 發佈來源；不再作全域互斥安裝單位 | project runtime 需與全域 plugin 解耦 |
| Codex | 四模式 | remote runtime archive/cache | 新增 | 每專案可釘 mode/version/SHA-256 |
| Codex | 四模式 | selector `project/local/user` | 修改 | 改寫 selector metadata，不 add/remove mode plugin |
| Codex | loader | marketplace/global install | 新增單一穩定 plugin／loader | 提供全域 hook 接線與 dispatch |
| Codex | `integrated-harness` | legacy global installer | 修改為相容 wrapper | 遷移 user fallback，不再獨占全域 mode plugin |
| Codex | 四模式 | shared source／同步副本 | 修改同步與 archive 產生測試；hook 行為本案原則不改 | runtime 內容仍需以 `shared/codex/` 為單一事實來源 |
| Claude | 四模式 | marketplace selector、native user、copy-in | 不修改 | Claude 有自己的 scope/plugin 契約，本案只解決 Codex 使用者層 plugin 衝突 |
| Copilot | DG、SDG | copy-in | 不修改 | Copilot 無本專案 selector／marketplace runtime，且仍為 Preview |
| 根層模式 | Claude copy-in、Codex runtime、Copilot copy-in | 行為 parity | 只更新受新安裝生命週期影響的測試／文件；安全規則不因本案改寫 | 避免把部署變更誤擴大成 hook 規則變更 |

文件／版本影響：

- `README.md`：必改；改寫 Codex 安裝、兩專案不同模式、離線與遷移說明。
- `CLI_REFERENCE.md`：必改；列出 loader、ref/source/offline/update/prune 與新 scope 語意。
- `ARCHITECTURE.md`：必改；記錄 loader、深 module、runtime cache、dispatch 資料流與新矩陣。
- `CHANGELOG.md`：必改 `[Unreleased]`；這是 Codex 可觀察安裝／切換行為變更。
- `VERSIONING.md`：需修改以釐清 runtime manifest identity 仍從屬 repo tag，不是新 per-plugin 版號；若實作採相同語意且現文已足夠，也至少加入明確 runtime 釘版段落。
- `docs/codex-marketplace.md`：必改完整生命週期與遷移指南。
- Claude plugin 版號：不調整；Claude 行為、介面與發佈內容均不變。
- Codex／Copilot：不得另造平台不承載的 plugin 版號；發布仍依 repo tag。依 `0.x` 政策，本案屬重大使用者流程變更，實際 repo tag 層級由主代理在發版時確認。

## 10. luna 分階段實作責任範圍

### Phase 0：契約與 fixture

luna 修改／新增：

- `codex/runtime-manifest.json` 與可重現 archive 產生／驗證腳本。
- runtime manifest schema fixture、四模式 entrypoint/event fixture。
- `tests/helpers/fake-codex`：把「單一全域 installed mode」模型改成「單一 loader installed + 多 project selector/cache」模型。

不得先改 hook 規則語意。

### Phase 1：深 module 與 adapters

luna 修改／新增：

- 新的 `scripts/codex-runtime-manager.py`（或同等單一 production module）：實作 `resolve/prepare/commit/verify/dispatch/prune`。
- production adapters 與 test adapters；不要把 downloader、filesystem fake 或 subprocess fake 暴露為 CLI interface。
- manifest、archive、path、digest、lock、atomic replace、rollback、redaction 單元／interface 測試。

### Phase 2：loader 發佈與安裝

luna 修改／新增：

- `codex/plugins/ai-guardrail-loader/`：manifest、skill、薄 hook entrypoint。
- `.agents/plugins/marketplace.json`：新增 loader；legacy modes 在遷移期可標示 available/deprecated，但 selector 不再安裝它們。
- `scripts/install-codex-guardrail-loader`、對應 verifier 與測試。
- user hooks 合併、保留其他 hooks、loader update rollback、loader uninstall 引用檢查。

### Phase 3：selector／verifier 與 scope 遷移

luna 修改：

- `scripts/select-codex-mode`
- `scripts/codex-mode-lib.sh`（縮減為 CLI/bootstrap 共用；核心規則不得在 Bash/Python 重複兩份）
- `scripts/verify-codex-mode`
- `tests/codex_mode_switch_test.sh`

luna 新增遠端、離線、A/B 專案、scope precedence、legacy absolute path、atomic pointer 與 rollback 測試。普通 select/update/remove 中不得出現 mode plugin add/remove。

### Phase 4：global installer 相容 wrapper

luna 修改：

- `scripts/install-codex-global-integrated-harness`
- `scripts/verify-codex-global-integrated-harness`
- `tests/codex_global_install_test.sh`

驗證它只管理 loader + user fallback，且不會拆除 project/local runtime 或其他 plugin。

### Phase 5：同步、文件與完整回歸

luna 修改實際受影響者：

- `README.md`
- `CLI_REFERENCE.md`
- `ARCHITECTURE.md`
- `CHANGELOG.md`
- `VERSIONING.md`
- `docs/codex-marketplace.md`
- Codex marketplace／shared sync／安裝結構／根層測試入口。

luna 不得修改 Claude、Copilot hook 或 Claude plugin 版號；若共同行為測試因 fixture 接線調整而需改，只能改測試 harness，不改其產品行為。

## 11. 驗收條件與必要測試

以下全部通過才可宣告完成：

1. A/B 同時不同模式：A=`harness@shaA`、B=`integrated-harness@shaB`；交錯送入各 hook 事件，dispatch 始終命中各自 runtime。切換 A 後 B 的 selector、cache identity 與結果 bytes 不變。
2. scope precedence：local 覆蓋 project，project 覆蓋 user；逐層 remove 後正確 fallback，移除任一層不碰其他層。
3. 離線 cache：先 online 安裝，再使 network adapter 必然失敗；正常 Codex hook 與 `--offline` verify 仍通過，且零網路呼叫。
4. 無網路首次安裝：cache miss 時明確 `E_RUNTIME_MISSING`／`E_NETWORK`，selector 與既有 hooks bytes 不變。
5. 更新失敗 rollback：涵蓋 manifest timeout、redirect denied、archive 截斷、SHA-256 mismatch、unsafe path、cache publish failure、selector atomic replace failure、post-verify failure；舊 runtime 仍可 dispatch。
6. 全域 plugin 不互相拆除：多次切換四模式及兩專案，fake-codex installed 集合始終只有 loader 與原先 unrelated plugins；不呼叫 legacy mode add/remove。
7. 舊格式相容：project TOML、local/user hooks 與 legacy global installer 三種 marker 均可遷移；遷移後無 checkout 絕對 hook 路徑。混合／殘缺舊格式拒絕並零變更。
8. checkout 相容：由舊 checkout 執行 selector 遷移後，移動／刪除 checkout，已選專案仍從 cache 執行；舊 selector 遇新 schema 時不得降級覆寫。
9. loader update rollback：新 loader 安裝或驗證失敗時 `current.json` 與 user hooks 保持舊版；成功更新不改任何專案 selector。
10. policy：選 IH 且個人政策不存在時建立；既有 policy 不覆寫，remove/update/prune 不刪除。
11. 安全 archive：拒絕 `../`、absolute、drive、UNC、symlink、hardlink、重複正規化名、超大檔與解壓炸彈；不得在 staging 外產生檔案。
12. symlink／TOCTOU：selector、scope parent、cache、entrypoint、hooks、policy 的 symlink／swap 注入均安全失敗；外部檔案不被修改。
13. 路徑字元：空白、單引號、反引號、`$()`、分號、反斜線與非 ASCII 專案路徑不造成命令注入，且 selector JSON 為 UTF-8。
14. Windows/Git Bash：支援只有 `python`、無可用 `python3` 的環境；不依賴 symlink 與 POSIX signal；原子 replace、lock、drive/UNC containment 測試通過。
15. Linux/macOS：執行權限、signal interruption、atomic rename 與完整回歸通過；未有實機環境者在交付中明列未驗，不得以 Windows 結果代稱。
16. 事件 parity：四模式現有事件、matcher、hook 順序、deny/ask/allow/updatedInput/SessionStart 可觀察結果與遷移前 fixture 一致。
17. 清理：dry-run 無變更；只刪未引用且過 grace period 的 digest child；引用中、rollback、lock 中 cache 均保留。
18. 同步與回歸：`scripts/sync-codex-hook-copies --check`、Codex marketplace／loader／mode switch／global install 專測、`bash tests/run_all.sh` smoke 與 `AGK_TEST_PROFILE=full bash tests/run_all.sh` 全部通過。

無網路測試必須使用會在任何網路 adapter 呼叫時立即失敗的 fake，而非依賴執行環境剛好斷線。更新與並行測試使用可控 ready marker，不用固定 sleep。

## 12. 仍需主代理確認的假設

實作前主代理只需確認下列會實質改變結果的事項：

1. 穩定 loader plugin 的正式名稱是否採 `ai-guardrail-loader`，以及 migration 期間四個 legacy mode plugin 是否仍留在 marketplace 顯示為 deprecated。
2. 正式 runtime archive 的承載位置：GitHub Release assets（建議，tag 不可變且便於 size/digest）或 repo raw/tarball；無論選哪個，manifest 必須固化 commit 與 SHA-256。
3. 首次未指定 `--ref` 時預設 `latest stable tag`（建議）或 `main`；普通重跑仍不得隱式更新。
4. `project` selector 是否預期提交版本控制；`local` selector 的 ignore 提示文字與是否提供獨立 `--write-ignore` 顯式選項。
5. user fallback 的 root 無 `.git`／`.codex` marker 時，是否接受 cwd 作 root（本規格建議接受並明示診斷），或要求 fail closed。
6. legacy mode plugin 自動移除是否限定於顯式 `install-codex-guardrail-loader --migrate`（本規格建議），避免普通專案切換產生全域副作用。
7. 正式支援平台矩陣是否要求 Windows Git Bash、Linux、macOS 全部為 release gate；若缺實機 runner，需批准哪些項目列為未驗風險。

除上述事項外，luna 應依本文件契約採最小、可回復且不改變四模式 hook 決策語意的實作，不再為內部命名或 fixture 細節等待確認。
