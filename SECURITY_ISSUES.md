# 安全稽核發現

稽核日期：2026-09-07  
修正驗證日期：2026-10-29

## 摘要

本次以靜態分析及不執行危險操作的函式層級測試，檢查 Claude Code、Codex、GitHub
Copilot 的 hook、共享安全規則，以及 Codex 遠端 runtime selector／loader。原始稽核共確認
4 項弱點；截至修正驗證日期均已有對應控制與回歸測試。專案不含 Web controller、route 或
ORM，因此 SQL injection、XSS、CSRF、auth bypass 與 mass assignment 不適用。

| 編號 | 原嚴重度 | 狀態 | 弱點 |
| --- | --- | --- | --- |
| AGK-001 | High | 已修正 | 危險命令攔截可被等價命令形式繞過 |
| AGK-002 | High | 已修正 | placeholder 判斷可讓真實憑證避開偵測 |
| AGK-003 | High | 已修正 | 遠端 runtime manifest 缺少獨立真實性驗證 |
| AGK-004 | Medium | 已修正 | 未受信任專案可用已快取 runtime 降級使用者防護模式 |

## AGK-001：危險命令攔截可被等價命令形式繞過

**嚴重度：High**

**狀態：已修正（2026-10-28）**。Claude 與 Codex 已加入 wrapper／Git 全域選項
正規化、shell 內嵌命令遞迴檢查及不透明直譯器保守攔截，並由跨模式測試覆蓋原始案例。

### 受影響範圍

- Claude Code：`harness`、`integrated-harness` 的 copy-in 與 plugin 副本
- Codex：`sensitive-data-guard`、`harness`、`integrated-harness` 的 shared、plugin 與 runtime archive 副本
- GitHub Copilot：目前 sensitive-data guard 不提供等價的危險命令防護，故不屬同一繞過面

### 證據

Claude 實作只比對原始字串的 regex；Codex 雖加入 `shlex`，但將第一個非選項參數視為
Git subcommand，未處理 `git -C` 等帶值全域選項，也未正規化 `sudo --` 或直譯器所執行的
等價檔案操作。

下列輸入在 Claude 與 Codex 的現行檢查函式都回傳放行：

```text
git -C /tmp/repo reset --hard
git -C /tmp/repo push origin main --force
sudo -- rm /tmp/important
python3 -c "import shutil; shutil.rmtree('/tmp/important')"
```

主要位置：

- `shared/codex/security_checks.py:69-176`
- `claude/plugins/harness/hooks/block_dangerous_commands.py:20-63`

### 影響

模型或惡意提示可用語意等價的命令避開「即使已核准也禁止模型執行」的紅線，造成檔案
刪除、Git 歷史破壞或受保護分支被強制覆寫。這會直接破壞此專案宣告的核心安全契約。

### 建議修正

1. 建立共享的命令正規化層，正確消耗 `git`、`sudo`、`env`、`command` 等 wrapper／全域
   選項，再對實際 executable、subcommand 與參數套用規則。
2. 對可執行任意程式碼的直譯器與 shell wrapper 採保守策略：無法可靠解析時要求人工核准，
   不應視為安全。
3. 將上述輸入及其 Windows／PowerShell 等價形式加入 Claude、Codex、Copilot 的行為一致性
   測試；先修改 shared 單一事實來源，再以既有同步流程更新所有副本及 runtime archive。

## AGK-002：placeholder 判斷可讓真實憑證避開偵測

**嚴重度：High**

**狀態：已修正（2026-10-28）**。placeholder 僅對擷取出的憑證值做完整比對；三平台
同步與 parity 測試涵蓋帶 `EXAMPLE`／`PLACEHOLDER` 前後綴的真實型值。

### 受影響範圍

- Claude Code：`sensitive-data-guard`、`harness`、`integrated-harness`
- Codex：`sensitive-data-guard`、`harness`、`integrated-harness`
- GitHub Copilot：`sensitive-data-guard`
- shared、copy-in、marketplace／plugin 與 Codex runtime archive 副本

### 證據

`PLACEHOLDER_PATTERN` 在整個命中內容中搜尋 `EXAMPLE`、`PLACEHOLDER`、`xxx` 等片段；只要
憑證本身含任一片段，整個規則就被略過，而不是判斷值是否為明確、完整的範例格式。

下列輸入在三個平台的現行檢查函式都未命中：

```text
password="ActualSecret123EXAMPLE"
api_key="live_Secret987PLACEHOLDER"
```

主要位置：

- `shared/codex/security_checks.py:30-54,196-224`
- `claude/plugins/harness/hooks/block_secrets.py:35-98`
- `copilot/plugins/sensitive-data-guard/hooks/block_secrets.py:29-77`

### 影響

真實密碼或 API key 只要天然含有或被附加特定字串，就能寫入檔案或命令而不被阻擋，可能
進入 Git、日誌、模型上下文或下游發布內容。

### 建議修正

1. 將 placeholder 判斷改成對「擷取出的值」做全值比對，僅允許明確格式，例如
   `YOUR_API_KEY`、`${API_KEY}`、`<api-key>`；不得以任意子字串命中即豁免。
2. 已辨識為供應商 token、私鑰或 JWT 的高信心規則不應套用通用 placeholder 豁免。
3. 新增包含 placeholder 子字串的真實型值、大小寫變體及前後綴測試，並加入跨平台 parity
   測試與同步測試。

## AGK-003：遠端 runtime manifest 缺少獨立真實性驗證

**嚴重度：High**

**狀態：已修正（2026-10-29）**。正式 GitHub runtime 只接受使用者從官方 Release
`Immutable runtime identity` 取得並明確提供的 40 位 immutable commit。manifest v2 不再
自報其所在 commit 或完整 archive URL；manager 以外部 commit、官方 repository 與受驗證
相對路徑推導 URL。branch、tag、隱含 `main` 與舊環境變數逃生口均被拒絕；local、test、
offline 與既有已快取 selector 不受影響。

### 受影響範圍

- Codex `ai-guardrail-loader`
- GitHub 來源的所有 Codex runtime 模式

### 證據

預設選取流程從可變的 `main` ref 下載 `runtime-manifest.json`，接著使用同一份 manifest 內的
SHA-256 驗證 archive。程式只確認 `release.commit` 是 40 位十六進位字串，未驗證 manifest
確實來自該 commit；也只限制 URL host，未將 repository、owner、ref／commit 與 archive
路徑綁定，更沒有獨立簽章或透明日誌證明。

主要位置：

- `scripts/codex-runtime-manager.py:173-217`
- `scripts/codex-runtime-manager.py:340-383`
- `scripts/codex-runtime-manager.py:1251-1276`

archive hash 能偵測傳輸損毀，但 manifest 與 archive 若一起被替換，驗證仍會成功，隨後
entrypoint 會由 loader 以目前使用者權限執行。

### 影響

上游儲存庫、可變 branch 或發佈流程遭入侵時，可形成 Codex hook 的供應鏈任意程式碼執行；
host allowlist 與 manifest 自帶 hash 無法阻止此情境。

### 建議修正

1. 以離線內建公鑰驗證 manifest 簽章，或採 Sigstore keyless 簽章並驗證固定 identity、issuer
   及透明日誌 inclusion proof；簽章金鑰／身分應與存放 manifest 的 branch 權限分離。
2. 正式安裝預設只接受 immutable commit 或已簽章 release tag，不使用 `main` 作為信任根。
3. 將 `release.source`、repository owner/name、外部 trusted commit 與 archive path 強制綁定；
   拒絕僅因位於任一 approved host 就被接受的來源。
4. 新增 manifest 與 archive 同時被替換、self-commit／URL 欄位、跨 repository source 及
   非 canonical path 的負向測試。

## AGK-004：未受信任專案可用已快取 runtime 降級使用者防護模式

**嚴重度：Medium**

**狀態：已修正（2026-10-28）**。project／local selector 必須在受保護 registry 中以
canonical path、scope 與 archive digest 完全匹配；未登錄 selector 不再覆蓋 user scope。

### 受影響範圍

- Codex `ai-guardrail-loader` 的 project selector

### 證據

loader 依 `local → project → user` 順序選擇 selector。專案內可版本控制的
`.codex/guardrail/runtime.json` 會優先於使用者預設；解析時只驗證 selector schema 與本機
cache 完整性，沒有確認該 selector 是由本機管理命令建立、已登錄於 selector registry，或
經使用者信任。攻擊者可提交指向受害者已快取之官方低防護模式的合法 selector。

主要位置：

- `scripts/codex-runtime-manager.py:463-470`
- `scripts/codex-runtime-manager.py:1152-1165`
- `scripts/codex-runtime-manager.py:1072-1087`（registry 已存在，但解析時未使用）

### 影響

使用者進入未受信任 repository 後，其 user-scope `integrated-harness`／`harness` 可被專案內
selector 降級成 `decomposition-gate` 或其他較弱模式。攻擊者不能藉此安裝未知 archive，
但能在受害者已快取對應 runtime 時降低原本期待的防護。

### 建議修正

1. loader 僅接受已存在於受保護 selector registry 且 path、scope、digest 完全一致的 project／
   local selector；registry 應位於使用者控制、專案不可寫的目錄。
2. 第一次信任專案 selector 或任何降級操作時，要求平台原生人工核准並記錄專案實體路徑與
   repository identity。
3. 文件明確要求 project selector 不得提交版本控制，並提供 `.gitignore` 範例；這只能作為
   緩解，不能取代 loader 的信任檢查。
4. 新增「未登錄 selector 不得覆蓋 user scope」及「已登錄 selector 可正常解析」測試。

## 已檢查但未列為弱點

- archive 解壓會拒絕絕對路徑、`..`、symlink、hardlink、device 與非一般檔案，並限制檔案
  數量、單一 archive 大小及總展開大小。
- runtime cache 在每次 dispatch 前驗證檔案清單、大小與 SHA-256，且 hook 子程序使用
  `shell=False` 與縮減後的環境變數。
- URL 僅允許 HTTPS、固定 host、443 port，且每次 redirect 都重新驗證來源。
- hook 載入失敗時，PreToolUse 輸出 deny，主要執行路徑採 fail closed。

## 驗證限制

本次未進行網路中間人、GitHub 帳號／Actions 入侵、Windows 原生 Codex、實際 Claude Code
或 VS Code Copilot UI 的動態測試；結論以 repository 內實作、同步副本與函式層級輸出為準。
