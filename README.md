# ai-guardrail-kit

本儲存庫提供 Claude Code 與 Codex 兩套平台實作。四種產品模式在各平台內皆應
**互斥、擇一啟用**；兩個平台的生命週期與核准語意不同，不應視為完全相同。
Claude Code 方案把 AI 協作開發從
單純的 prompt 約定，提升為「軟性決策規則 ＋ 硬性工具關卡（PreToolUse
hooks）」。三個目錄**功能與用途各自獨立、不可同時安裝**，其中
`integrated-harness` 是整合另外兩者能力的完整版，而非疊加安裝。

## 需求環境

- [Claude Code](https://docs.claude.com/en/docs/claude-code) CLI
- Python 3.9+（四種模式統一版本需求）——**唯一**執行期依賴，僅需直譯器本身，
  hooks 只用標準函式庫，不需 `pip install` 任何套件。系統只要有
  `python3`、`python`、`py`（Windows）任一種可執行別名即可，`settings.json`
  會依序探測並使用第一個可用的；若三者皆不存在，hook 會直接失敗（fail
  closed，不會誤放行）——這種情況請自行安裝 Python 3.9+ 並確認已加入 PATH，
  安裝完成後開新的終端機／Claude Code session 再試一次。
- git（`integrated-harness` 的核准機制以 SHA-256 綁定拆解文件內容）

## 快速開始

### Codex

Codex 使用 repository marketplace manifest、[`codex/`](codex/) 內的 plugin 與專案 hook
設定；完整的安裝、切換、更新、驗證及限制請見
[`docs/codex-marketplace.md`](docs/codex-marketplace.md)。Codex 四種模式皆需
Python 3.9+，不可沿用下列 Claude copy-in 安裝步驟。

從 GitHub 註冊 Codex marketplace：

```bash
codex plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --ref main --sparse .agents --sparse codex/plugins
```

`--sparse .agents --sparse codex/plugins` 下載 marketplace manifest 與 plugin 套件。註冊後請依照
[`docs/codex-marketplace.md`](docs/codex-marketplace.md) 使用 selector 選擇並啟用其中一種模式；也可先安裝
單一 plugin，例如：

```bash
codex plugin add decomposition-gate@ai-guardrail-kit
```

使用 selector 選擇 `integrated-harness` 時，若個人政策檔不存在，會建立
`~/.codex/guardrail/orchestration-policy.md`；既有個人政策不會被覆寫或在移除
模式時刪除。完整政策語意請見
[`codex/plugins/integrated-harness/README.md`](codex/plugins/integrated-harness/README.md)。

若要將 `integrated-harness` 設為所有 Codex 專案的全域預設，註冊 marketplace 後於
本儲存庫執行一次：

```bash
./scripts/install-codex-global-integrated-harness
./scripts/verify-codex-global-integrated-harness
```

此操作只管理 `~/.codex/hooks.json` 中帶有 ai-guardrail-kit 標記的三個 hooks，
保留既有的其他全域 hooks。解除安裝與驗證：

```bash
./scripts/install-codex-global-integrated-harness --remove
./scripts/verify-codex-global-integrated-harness --no-installed
```

完整行為與限制請見 [`docs/codex-marketplace.md`](docs/codex-marketplace.md)。

### Claude Code

Claude also provides a repository marketplace with mutually exclusive project
and local mode selection. See
[`docs/claude-marketplace.md`](docs/claude-marketplace.md) for registration,
selection, update, verification, removal, and scope behavior.

從 GitHub 註冊 Claude Code marketplace（目前專案）：

```bash
claude plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git --scope project --sparse .claude-plugin claude/plugins
```

`--sparse .claude-plugin claude/plugins` 下載 marketplace manifest 與 plugin 套件。
如需僅供本機使用，將 `--scope project` 改為 `--scope local`。註冊後請依照
[`docs/claude-marketplace.md`](docs/claude-marketplace.md) 使用 selector 選擇並啟用其中一種模式。

三者皆為「複製即用（copy-in）」，沒有套件安裝或執行時相依，依需求擇一複製
對應目錄下的 `.claude/` 到你的專案（若專案已有 `.claude/settings.json`，
請手動合併 hooks 區塊，勿直接覆蓋）：

```bash
# 範例：只需要拆解品質閘門
cp -r decomposition-gate/.claude your-project/

# 範例：只需要人類核准與安全 hook
cp -r harness/.claude your-project/

# 範例：完整方案
cp -r integrated-harness/.claude your-project/

chmod +x your-project/.claude/hooks/*.py
```

詳細設定與核准流程請見各目錄的 `README.md`。

## 移除 Plugin

### Claude Code

先移除選定的模式，再移除 marketplace 註冊（`.` 可換成目標專案路徑，
`--scope` 需與安裝時一致）：

```bash
./scripts/select-claude-mode --remove --scope project .
./scripts/verify-claude-mode --no-managed-mode .
claude plugin marketplace remove ai-guardrail-kit
```

`select-claude-mode --remove` 會清除找到的所有 managed mode（跨 `project`／
`local` 兩種 scope），移除後請開新的 Claude Code session 讓 hooks 確實卸載。
完整行為見 [`docs/claude-marketplace.md`](docs/claude-marketplace.md)。

### Codex

若曾用 selector 啟用某一模式，先移除該模式再移除 marketplace：

```bash
codex plugin remove integrated-harness@ai-guardrail-kit
codex plugin marketplace remove ai-guardrail-kit
```

若曾執行過全域預設安裝（`install-codex-global-integrated-harness`），
需另外解除：

```bash
./scripts/install-codex-global-integrated-harness --remove
./scripts/verify-codex-global-integrated-harness --no-installed
```

此指令只移除帶有 ai-guardrail-kit 標記的 hooks，不影響其他既有全域 hooks；
既有個人政策檔 `~/.codex/guardrail/orchestration-policy.md` 不會被自動刪除，
需自行決定是否保留或手動刪除。完整行為見
[`docs/codex-marketplace.md`](docs/codex-marketplace.md)。

### copy-in（複製即用）安裝

若是以 `cp -r .../.claude your-project/` 方式複製安裝（未透過 marketplace），
移除方式為手動刪除複製進去的檔案與合併過的 hooks 設定：

```bash
rm -rf your-project/.claude/hooks your-project/.claude/plan
rm your-project/CLAUDE.md your-project/ORCHESTRATOR.md 2>/dev/null
```

若 `.claude/settings.json` 是與既有設定手動合併而非整份複製，請手動移除
其中對應本 kit 的 hooks 區塊，不要整份刪除 `settings.json`。

## 四種模式總覽

| 目錄 | 一句話定位 | 拆解檢查 | 人類核准 | 安全 Hook | 治理政策 |
| --- | --- | --- | --- | --- | --- |
| [`decomposition-gate/`](decomposition-gate/) | 任務拆解品質閘門（流程紀律） | 有 | 無 | 無 | 無 |
| `sensitive-data-guard` plugin | 明文秘密與個資的獨立防線 | 無 | 無 | 僅敏感資料 | 無 |
| [`harness/`](harness/) | 人類核准與安全 hook 防線（授權控制） | 無 | 有 | 有 | 無；歷史編排提示稿已淘汰 |
| [`integrated-harness/`](integrated-harness/) | 前兩者的整合版 ＋ 精簡治理政策 | 有 | strict 模式有 | 有 | 內建授權、外部副作用、驗收、成本與失敗揭露規範 |

## Claude Code／Codex 完整功能對照

下表以目前儲存庫中的實作為準。`—` 表示該模式不提供該能力；「平台原生差異」
不代表缺陷，而是兩邊 hook 輸入格式、寫入工具及核准流程不同。四種模式在同一平台內
必須互斥、擇一啟用。

縮寫：`DG`＝`decomposition-gate`、`SDG`＝`sensitive-data-guard`、`H`＝`harness`、`IH`＝`integrated-harness`。

`sensitive-data-guard` 是第四種獨立安裝模式：阻擋明文密碼、API Key、Token、憑證及
提示中的疑似個資，並將受支援寫入內容中的個資去識別化；刻意不包含危險命令、拆解、
人工核准與編排。Claude 與 Codex 均以 marketplace selector 安裝此模式。

| `sensitive-data-guard` 功能 | Claude | Codex |
| --- | --- | --- |
| 明文秘密／憑證阻擋 | `Write`／`Edit`／`MultiEdit`／`NotebookEdit`／`Bash` | `exec_command`／`apply_patch` |
| 提示文字個資阻擋 | `UserPromptSubmit` | `UserPromptSubmit` |
| 寫入內容個資去識別化 | 四種寫入工具的文字欄位 | `apply_patch` 的受支援文字欄位 |
| 個資種類 | 身分證、手機、Email、地址、信用卡、學號、護照 | 同 Claude |
| 不包含 | 危險命令、拆解、人工核准、編排 | 同 Claude |

下方大表接續比較原有三種治理模式；SDG 的完整能力已獨立列於上表。

### 各模式執行期能力

| 功能 | Claude DG | Claude H | Claude IH | Codex DG | Codex H | Codex IH |
| --- | --- | --- | --- | --- | --- | --- |
| 主要定位 | 先拆解再寫入 | 人工核准＋安全防線 | 拆解、政策、核准、安全與編排 | 先拆解再寫入 | 原生逐次核准＋安全防線 | 拆解、政策、原生核准、安全與編排 |
| `PreToolUse` 確定性關卡 | 有 | 有 | 有 | 有 | 有 | 有 |
| 拆解文件 | `.claude/plan/decomposition.md` | — | `.claude/plan/decomposition.md` | `.codex/guardrail/plan/decomposition.md` | — | `.codex/guardrail/plan/decomposition.md` |
| 拆解必要標記 | `已知資訊`、`缺少的資訊`、至少一個 `【假設】` | — | 同 DG | 同 Claude DG | — | 同 DG，另需允許修改範圍 |
| 未完成拆解時封鎖寫入 | 有 | — | 有 | 有 | — | 有 |
| 唯讀操作可在關卡前執行 | 有 | 有 | 有 | 有 | 有 | 由註冊 hook 與 Codex 原生唯讀流程處理 |
| 緊急停用拆解關卡 | 人類建立 `.claude/plan/.gate_disabled` | — | — | 人類建立 `.codex/guardrail/plan/.gate_disabled` | — | — |
| 防止模型自建／修改逃生口 | 有，檔案工具與 Bash 都攔截 | — | — | 有，`apply_patch` 與 `exec_command` 都攔截 | — | — |
| 人類核准方式 | — | 人類建立 `.claude/.plan_approved` | `strict` 下執行 `approve_plan.py` | — | 每個受管寫入使用 Codex 原生 `ask` | `strict`／`standard` 依政策使用 Codex 原生 `ask` |
| 核准有效範圍 | — | 旗標建立後 60 分鐘 | 綁定拆解文件 SHA-256，60 分鐘 | — | 單次工具呼叫 | 單次工具呼叫；提示包含目前計畫 SHA-256 |
| 防止模型自我核准 | — | 有，禁止工具操作核准旗標 | 有，禁止修改核准紀錄與政策 | — | 由 Codex 原生核准 UI 負責 | 由 Codex 原生核准 UI 負責 |
| 政策模式 | — | — | `strict`／`standard`／`light` | — | — | `strict`／`standard`／`light` |
| 專案政策檔 | — | — | `.claude/orchestration-policy.md` | — | — | `.codex/guardrail/orchestration-policy.md` |
| 個人政策 fallback | — | — | `~/.claude/orchestration-policy.md` | — | — | `~/.codex/guardrail/orchestration-policy.md` |
| 無政策或政策無效 | — | — | fail closed 為 `strict` | — | — | fail closed 為 `strict`，空 Bash allowlist |
| 允許修改範圍 | — | — | `strict`／`standard` 強制；`light` 不解析、不強制 | — | — | 所有模式的 `apply_patch` 都強制範圍；`light` 只免除 patch 的 `ask` |
| `strict` Bash allowlist | — | — | 有；不在清單的一般 Bash 直接拒絕 | — | — | 有；符合清單後仍須原生 `ask` |
| `standard` 行為 | — | — | 拆解＋範圍，免人工核准 | — | — | 拆解＋範圍，`apply_patch`／`exec_command` 仍原生 `ask` |
| `light` 行為 | — | — | 只要求基本拆解；免範圍與人工核准 | — | — | 範圍內 `apply_patch` 免 `ask`；`exec_command` 仍 `ask` |
| 永久危險命令阻擋 | — | 有 | 有 | — | 有 | 有 |
| 危險命令涵蓋 | — | 毀滅性刪除、force push、下載即執行、`find -exec`、命令替換等 | 同 H | — | 與 Claude 對齊的 token 化判定＋regex fallback | 同 H |
| 明文秘密／憑證阻擋 | — | 有 | 有 | — | 有 | 有 |
| 秘密判定特殊處理 | — | 區分環境變數引用與硬編碼值 | 同 H | — | 另支援 Bash `${VAR:-fallback}` 與未加引號指派 | 同 H |
| 提示文字個資阻擋 | — | 有，`UserPromptSubmit` 命中即整段阻擋 | 有 | — | 有，`UserPromptSubmit` 命中即整段阻擋 | 有 |
| 寫入內容個資去識別化 | — | `Write`／`Edit`／`MultiEdit`／`NotebookEdit` 的文字欄位 | 同 H | — | `apply_patch` 等 hook 輸入中的受支援文字欄位 | 同 H |
| 個資種類 | — | 身分證、手機、Email、地址、信用卡、學號、護照 | 同 H | — | 同 Claude H | 同 H |
| 信用卡二次驗證 | — | 13–19 碼候選值通過 Luhn 才命中 | 同 H | — | 同 Claude H | 同 H |
| 學號／護照判定 | — | 需鄰近標籤文字，降低裸編號誤判 | 同 H | — | 同 Claude H | 同 H |
| `SessionStart` 協定提醒 | — | — | 有，注入基本提醒與可讀取的推理協定 | — | — | 有，注入基本提醒並在可用時讀取推理協定 |
| 深廣思考／工作流程指引 | 推理協定文件 | 無；歷史提示稿已淘汰 | 推理協定＋精簡治理政策 | plugin skill | plugin skill | plugin skill＋thread 開場提醒 |
| 治理政策 | — | — | 有：授權、外部副作用、驗收、成本與失敗揭露 | — | — | 有：以 Codex skill 與政策呈現 |
| 異常 hook 輸入 | 保守拒絕寫入 | 關卡採 fail closed | 關卡採 fail closed | 結構驗證失敗即 deny | 結構驗證失敗即 deny | 結構驗證失敗即 deny |

### 安裝、生命週期與維護能力

| 項目 | Claude Code | Codex |
| --- | --- | --- |
| Repository marketplace | 有，manifest 位於 `.claude-plugin/marketplace.json` | 有，manifest 位於 `.agents/plugins/marketplace.json` |
| 可選模式 | `decomposition-gate`、`sensitive-data-guard`、`harness`、`integrated-harness` | 同 Claude |
| 模式互斥 selector | `scripts/select-claude-mode` | `scripts/select-codex-mode` |
| 安裝狀態驗證 | `scripts/verify-claude-mode` | `scripts/verify-codex-mode` |
| 支援 scope | `project`、`local`；不支援 `user` | 依 Codex marketplace／專案設定；另有 IH 全域預設安裝器 |
| copy-in 發佈 | 有，根目錄三個模式的 `.claude/` 可直接複製 | 無；不可沿用 Claude copy-in |
| 全域預設 | 無專用全域安裝器 | IH 可用 `install-codex-global-integrated-harness` 安裝到 `~/.codex/hooks.json` |
| 保留其他既有 hooks | selector 管理自己的 plugin 狀態 | 全域安裝器只管理帶 kit 標記的 hooks，保留其他 hooks |
| 政策範本安裝 | IH 由使用者建立專案或個人政策 | selector 選 IH 時，個人政策不存在才建立；不覆寫既有檔 |
| 生效時機 | 選擇、更新或移除後開新 Claude Code session | 選擇、更新或移除後開新 Codex thread |
| Python | 3.9+；依序探測 `python3`／`python`／`py` | 3.9+；selector 探測並寫入 hook 命令 |
| 額外 Python 套件 | 無，現有 hooks 僅用標準函式庫 | 無，現有 hooks 僅用標準函式庫 |
| 共用程式來源 | PII 三件組以 `shared/claude/` 為唯一審核來源，同步腳本產生 plugin 與 copy-in 副本；`block_secrets`／`block_dangerous` 為分歧分支，由 parity 行為測試守護 | `shared/codex/` 為唯一審核來源，透過同步腳本產生 plugin 副本 |
| 統一回歸入口 | `tests/run_all.sh` | `tests/run_all.sh` |

### 已知共同限制

| 限制 | Claude Code | Codex |
| --- | --- | --- |
| 附件送模前個資掃描 | 不支援；目前只掃描 `prompt` 純文字 | 不支援；目前只掃描 `prompt` 純文字 |
| PDF／Office 文件解析 | 不支援 | 不支援 |
| 圖片 OCR／證件／人臉／車牌辨識 | 不支援 | 不支援 |
| 混淆或間接執行的完整偵測 | regex／token 規則只能降低風險，不能保證全攔截 | 同 Claude |
| 學號／護照裸資料 | 無鄰近標籤時可能漏判 | 同 Claude |
| Hook 是否等同沙箱 | 否，仍須搭配 Claude 權限、沙箱與人工審查 | 否，仍須搭配 Codex 權限、沙箱與人工審查 |

兩平台的個資「規則能力」目前已對齊，但 hook I/O 與程式來源仍是兩套實作；修改任一端
時必須同步評估另一端，不能假設會自動同步。附件掃描的評估提案記錄於
`.docs/vault/decisions/2026-07-23-local-attachment-pii-scanner-proposal.md`，目前尚未實作。

## 為何分成四種模式

四種模式不是由弱到強後全部疊加安裝，而是四個互斥的產品邊界。拆分的主要價值是讓
使用者依實際治理需求採用最小必要能力，避免只需要一道簡單關卡時，被迫承擔政策、
核准、個資與編排的全部操作成本。

| 模式 | 優點 | 缺點／代價 | 何時必要 | 保留必要性 |
| --- | --- | --- | --- | --- |
| `decomposition-gate` | 最小、容易理解；只約束「先拆解、後修改」；不引入人工核准、政策與安全規則的額外摩擦；適合個人、教學與 PoC | 不是授權控制；模型能自行完成拆解後繼續；不阻擋危險命令、秘密或個資；不能取代沙箱與人工審查 | 只想改善思考與工作紀律，不希望每次修改都要求人工核准時 | **有條件必要**：提供最低摩擦的獨立入口；若只剩完整版，這類使用者會被迫承擔不需要的治理成本 |
| `sensitive-data-guard` | 將資料外洩防線獨立安裝；阻擋明文秘密與提示詞個資，並遮罩寫入內容的個資；不改變團隊工作流程 | 不阻擋危險命令、不要求拆解或人工核准；規則式辨識仍可能誤判或漏判，不能取代完整 DLP | 已有自己的流程與權限控制，只想加裝敏感資料檢查時 | **必要**：讓資料保護成為可獨立採用的最小能力，不必連帶安裝核准與編排 |
| `harness` | 不要求採用本專案的拆解／編排方法；可直接補上人工核准、危險命令、秘密與個資防線；容易接到既有 SDLC、規格或外部編排流程 | 本身不驗證拆解品質與修改範圍；Claude 與 Codex 的人工核准生命週期不同；安全規則仍有 regex／token 判定盲點 | 團隊已有自己的計畫、工單、編排或審批流程，只缺確定性施作授權與安全底線時 | **有條件必要**：避免強迫成熟團隊改用本專案的拆解格式與編排規範 |
| `integrated-harness` | 一次提供拆解、範圍、政策模式、人工核准、安全防線、個資保護、SessionStart 提醒及精簡治理政策；治理邊界最完整 | 設定與學習成本最高；strict 模式摩擦最大；政策錯誤可能導致 fail closed；兩平台的 `standard`／`light` 行為不同，維護與測試矩陣最大 | 新專案、多人協作、高風險資料、正式系統，或需要明確授權與稽核邊界時 | **必要**：作為完整治理方案，避免使用者自行拼裝 DG 與 H 後產生 hook 順序、政策或核准語意衝突 |

### 拆成三個的整體優缺點

| 面向 | 拆成三個的優點 | 拆成三個的缺點 |
| --- | --- | --- |
| 最小權限與最小摩擦 | 每個專案只啟用真正需要的關卡 | 使用者安裝前必須先理解並選擇模式 |
| 邊界清楚 | 流程紀律、資料保護、授權安全、完整治理四種需求不混在同一組開關 | 功能說明、安裝流程與版本需要分別維護 |
| 相容既有流程 | H 不強迫採用本專案拆解格式；DG 不強迫人工核准 | 共用安全與 PII 修補必須同步到多個發佈副本 |
| 風險隔離 | 簡單模式不會因複雜政策解析錯誤而被影響 | Claude／Codex × 四模式形成較大的回歸測試矩陣 |
| 完整方案 | IH 提供經過設計的整合順序，不需使用者自行疊加 | IH 與獨立模式之間可能發生功能漂移，需 parity／sync 測試守護 |

### 是否技術上一定要三個 Plugin

**不是。** 技術上可以改成單一 plugin，再用設定切換 `decomposition`、`security`、
`integrated` profile；但這會把互斥選擇從安裝階段移到執行期分支，增加錯誤設定、
未知組合、政策解析與測試複雜度。尤其安全 hook 若被個別開關誤關閉，失敗模式會比
「明確選錯 plugin」更不容易察覺。

目前保留三個的必要性主要是**產品與治理邊界**，不是程式執行上的硬性限制：

1. `decomposition-gate` 服務只需要流程紀律的低摩擦使用者。
2. `sensitive-data-guard` 服務只需要秘密與個資防線、但不想改變流程的團隊。
3. `harness` 服務已有既有規劃／編排，只需要授權與安全防線的團隊。
4. `integrated-harness` 服務需要完整預設治理、且不應自行拼裝 hooks 的專案。

若未來觀察到獨立 DG 或 H 幾乎沒有實際使用者，或多副本同步成本持續造成安全漂移，
才適合評估合併為單一 plugin；合併前應先具備設定 schema、非法組合拒絕、升級遷移、
fail-closed 預設與六種現有行為的相容測試。

## 各目錄說明

### decomposition-gate — 先想清楚、再動手

以 PreToolUse hook 封鎖寫入類工具，直到 Claude 完成任務拆解並寫入
`.claude/plan/decomposition.md`（須含「已知資訊」「缺少的資訊」與至少一個
`【假設】` 標記）。搭配「深廣思考協定」五階段（拆解 → 探索 → 深化 →
對抗式審查 → 輸出前驗證）。

- 屬「流程紀律」而非「授權控制」：拆解文件可由模型自行完成，不能視為
  人工審批或安全沙箱。
- 逃生口 `.claude/plan/.gate_disabled` 存在時停用關卡（緊急修復用）；此檔
  **只能由人類在自己的終端機建立**，模型透過寫入工具或 Bash 自建一律被 deny，
  避免模型自我停用關卡。
- 適用：個人開發、教學、PoC，或只想強制留下任務拆解的專案。

### harness — 人類核准與安全底線

一組可獨立複製到專案的 hooks：未取得人類核准（`touch .claude/.plan_approved`，
60 分鐘有效）時攔截一切寫入；另有兩道獨立防線——攔截疑似硬寫的憑證，以及
永久攔截毀滅性 Bash 指令（不因核准而豁免）。使用者提交提示時另偵測疑似個資
（身分證字號、手機、Email、地址、信用卡卡號、學號、護照號碼）即整段阻擋；寫入類工具偵測到疑似個資時則自動
去識別化改寫後放行（`guard.py` 以 `hookSpecificOutput` JSON 傳遞 deny／allow
決策）。歷史 `fable-orchestrator-prompt.md` 已標示 deprecated，只為既有連結與使用者
保留；產生編排提示稿不再是 `harness` 的功能賣點，新專案不應使用。

- 屬「授權控制」：核准旗標只能由人類在自己的終端機操作，模型無法自我核准。
- 適用：已有計畫／編排規範、需要補上確定性施作授權與安全底線的專案。

### integrated-harness — 完整部署方案

整合 `decomposition-gate` 的拆解品質檢查與 `harness` 的人類核准及安全 hooks，再加上
精簡治理政策：`ORCHESTRATOR.md` 不再教導一般任務分解、模型路由或代理調度，只保留
人類授權、外部副作用、修改範圍、驗收證據、成本與失敗揭露，並附維護說明
（`MAINTENANCE.md`）。核准以
`python3 .claude/hooks/approve_plan.py`（Windows 環境無 `python3` 時改用 `python`）
綁定拆解文件的 SHA-256，並提供
`strict`／`standard`／`light` 三種核准模式（由人類在政策檔設定，模型不得修改）。政策檔以
專案 `.claude/orchestration-policy.md` 優先，專案檔不存在時讀取個人層級
`~/.claude/orchestration-policy.md`，兩處皆無一律回落 `strict`。

- 適用：多人協作、高風險資料、正式系統，以及需要稽核軌跡的專案。
- 除本目錄自帶的 `tests/` 外，儲存庫根層 `tests/` 的回歸測試涵蓋
  全部四種模式與兩個平台（`decomposition-gate` 另有
  `tests/smoke_test.sh`）。

## 如何選擇

1. 只想強制「先拆解、後實作」的思考紀律 → `decomposition-gate`
2. 只想加裝秘密與個資檢查，不需要人工核准或編排 → `sensitive-data-guard`
3. 已有自己的編排規範，只缺人工授權與安全底線 → `harness`
4. 需要完整方案（拆解品質 ＋ 人類授權 ＋ 安全底線 ＋ 編排規則）→
   `integrated-harness`

Claude copy-in 安裝方式見各根目錄模式的 `README.md`；三者彼此沒有執行時相依。
Codex 請使用 marketplace plugin 與 selector，不可沿用 copy-in 步驟。

## 維護注意事項

- 三個目錄的閘門 hook **不得互相覆蓋**：`decomposition-gate` 的
  `decomposition_gate.py` 檢查「拆解是否完成」；`harness` 的 `plan_gate.py`
  檢查「人類是否核准」；`integrated-harness` 的 `plan_gate.py` 兩者皆查。
- `harness` 與 `integrated-harness` 的 `block_secrets.py`、
  `block_dangerous_commands.py` 為同源分支：修補任一邊的繞過手法時，
  須檢查另一邊是否需同步移植（詳見
  [`integrated-harness/MAINTENANCE.md`](integrated-harness/MAINTENANCE.md)），
  並把攻擊樣本加入 `tests/claude_hook_parity_test.sh` 的共同行為語料，
  由該測試守護兩邊判定一致。
- 回歸測試統一入口為 `tests/run_all.sh`，CI 與人工回歸皆應以它執行
  全部測試；也可單獨執行個別 `tests/*_test.sh`。
- `harness` 與 `integrated-harness` 的 `settings.json` 只掛載 `guard.py` 統一進入點，
  由它在單一直譯器行程內依序執行三道檢查；hook 檔案須整組複製，
  修改任一檢查腳本後應執行 `tests/claude_guard_test.sh` 回歸。
- Claude plugin 與 copy-in 的 PII 三件組（`pii_patterns.py`／`block_pii_prompt.py`／
  `redact_sensitive_info.py`）以 `shared/claude/` 為唯一審核來源；修改該目錄後執行
  `scripts/sync-claude-hook-copies` 更新 5 份發佈副本（3 plugin＋2 copy-in），再以
  `scripts/sync-claude-hook-copies --check`（即 `tests/claude_shared_sync_test.sh`）確認
  沒有漂移。`block_secrets.py`／`block_dangerous_commands.py` 為刻意分歧分支，不在同步
  範圍，改由 `tests/claude_hook_parity_test.sh` 行為守護。
- copy-in（`harness/.claude/hooks`、`integrated-harness/.claude/hooks`）與 marketplace
  plugin 的**非 PII** hook（`guard.py`／`plan_gate.py`／`block_secrets.py`／
  `block_dangerous_commands.py`／`approve_plan.py`／`inject_protocol.py`）為兩份平行副本，
  由 `tests/claude_copyin_parity_test.sh` 守護逐字節一致；`integrated-harness/plan_gate.py`
  的核准命令路徑差異（copy-in 用 `.claude/hooks/`、plugin 用 `${CLAUDE_PLUGIN_ROOT}`）為
  已知刻意例外。修改上述任一份後，兩份都要一起改。
- Codex plugin 的共用 hook 以 `shared/codex/` 為唯一審核來源；修改該目錄後執行
  `scripts/sync-codex-hook-copies` 更新可攜式 plugin 副本，再以
  `scripts/sync-codex-hook-copies --check` 與完整回歸測試確認沒有漂移。
- Codex `harness` 與 `integrated-harness` 以 `security_guard.py` 在單一 Python
  程序內依序執行危險命令與秘密寫入檢查；計畫閘門與個資改寫因決策語意不同，
  仍維持獨立 hook。
- Claude 與 Codex 的個資規則皆以 Luhn 驗證 13–19 碼信用卡候選值；學號與護照
  號碼採標籤錨定，需鄰近 `學號`／`student id`／`護照`／`passport` 等文字才命中。
- Regex hooks 是防線不是保證，無法涵蓋混淆、間接執行等所有變形；須搭配
  Claude Code 權限設定、SAST、Secret Manager 與人工審查。
