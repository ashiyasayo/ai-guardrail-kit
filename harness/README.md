# Harness — 人類核准與安全 Hook 防線

本目錄是一組可獨立複製到 Claude Code 專案的 PreToolUse hooks。它以人工核准旗標
控制寫入，並另行攔截疑似憑證與高危險 Bash 指令。本目錄不負責產生或強制代理
編排；歷史提示稿只為相容既有使用者保留，已標示 deprecated。

## 功能與用途分析

| 面向 | 說明 |
| --- | --- |
| 核心功能 | 未取得人類核准時，只允許保守白名單中的唯讀 Bash；一般寫入與其他 Bash 均攔截 |
| 人類控制 | 人類以 `.claude/.plan_approved` 表示核准，旗標預設有效 60 分鐘 |
| 安全防線 | 掃描即將寫入的憑證樣式，並永久攔截毀滅性或高風險 Bash 指令 |
| 個資防線 | 使用者提交提示時偵測疑似個資（身分證字號、手機、Email、地址、信用卡卡號、學號、護照號碼），整段阻擋並提示改以去識別化內容重送；寫入類工具偵測到疑似個資時則自動去識別化改寫後放行 |
| 主要用途 | 為已有計畫／編排規範的專案補上確定性的施作授權與安全底線 |
| 適用情境 | 需要人工先核准再修改，或要為 orchestrator 與 subagent 套用共同 hook 的團隊專案 |
| 不提供 | 不驗證拆解文件內容、不把核准綁定特定計畫、不產生或強制代理編排 |

與 `decomposition-gate` 最大差異是：它的 `decomposition_gate.py` 檢查
「拆解是否完成」，本目錄的 `plan_gate.py` 檢查「人類是否核准」。
若兩種條件都需要，應使用 `integrated-harness`，不要把兩支閘門腳本互相混用。

## 檔案職責

| 檔案 | 事件／類型 | 職責 |
| --- | --- | --- |
| `guard.py` | PreToolUse / `Write\|Edit\|MultiEdit\|NotebookEdit\|Bash` | 統一進入點：一次啟動直譯器，依序執行下列四道檢查（前三道首個攔截即生效，deny 以 `hookSpecificOutput` JSON 輸出；輸入異常時仍 stderr + exit 2 fail closed），降低每次工具呼叫的啟動開銷 |
| `plan_gate.py` | 檢查模組（亦可獨立執行） | 未經核准攔截寫入性操作；唯讀白名單放行；禁止模型操作核准旗標 |
| `block_secrets.py` | 檢查模組（亦可獨立執行） | 攔截疑似 API Key、Token、密碼、私鑰與含密碼的連線字串 |
| `block_dangerous_commands.py` | 檢查模組（亦可獨立執行） | 攔截刪除、毀損資料庫、破壞 Git 歷史、停用安全服務等紅線操作 |
| `redact_sensitive_info.py` | 檢查模組（亦可獨立執行，供 `guard.py` 匯入） | 寫入類工具（Write/Edit/MultiEdit/NotebookEdit）內容偵測到疑似個資時不阻擋，改寫為遮罩後內容並放行，與 `integrated-harness` 逐字元相同 |
| `block_pii_prompt.py` | UserPromptSubmit | 使用者提交提示當下偵測疑似個資（身分證字號、手機、Email、地址、信用卡卡號、學號、護照號碼），整段阻擋並提示改以去識別化內容重送；本 hook 只能阻擋，改寫放行由 `redact_sensitive_info.py` 負責 |
| `pii_patterns.py` | 規則模組（供 `block_pii_prompt.py` 與 `redact_sensitive_info.py` 匯入） | 個資偵測規則單一事實來源，與 `integrated-harness` 逐字元相同，改規則只需改這一份 |
| `settings.json` | Claude Code 設定 | 將 `guard.py` 掛載到 PreToolUse（五個檔案須一起複製，`guard.py` 匯入其餘四支）；另將 `block_pii_prompt.py` 掛載到 UserPromptSubmit |
| `fable-orchestrator-prompt.md` | 已淘汰的相容資產 | 歷史編排提示稿；新專案不應使用，未來主要版本可移除 |
| `MAINTENANCE.md` | 維護說明 | 設計理由、與 `integrated-harness` 的差異與跨產品同步原則（維護者閱讀，不需複製到專案） |
| `CLAUDE.md` | 專案指引範本 | 命名規範（識別字英文、註解與回覆用台灣繁體中文）、架構原則（Clean Architecture／SOLID／TDD-BDD、既有系統最小變動）與 Spec by Example（需求以具體範例表達並可轉為可執行測試） |

分工原則：`plan_gate` 管「未核准的一般寫入」；
`block_dangerous_commands` 管「永遠不准模型執行」的紅線。
兩者獨立，互不依賴。

## 個資防護機制：如何攔截、如何去識別化

兩支個資 hook 共用同一份規則來源 `pii_patterns.py`（`RULES`：規則名稱、
正規表示式、遮罩函式、驗證函式四元組）。判定命中為「regex 命中 **且**
（驗證函式為 `None` 或驗證函式回傳 `True`）」；驗證函式讓需要額外邏輯的規則
（如信用卡 Luhn checksum）也能納入，而不必放寬 regex 造成大量誤判。兩層防線
只是「命中後怎麼處理」不同：

| 目前規則 | 判斷方式（`pii_patterns.py`） |
| --- | --- |
| 台灣身分證字號 | 開頭大寫字母 + `1`或`2` + 8 碼數字（如 `A123456789`） |
| 手機號碼 | `09` 開頭 10 碼數字，容許 `-` 或空白分隔 |
| Email | 標準 `local@domain` 格式 |
| 地址 | 縣市＋（區／鄉／鎮／市，可省略）＋路／街／大道（可含段）＋門牌號 |
| 信用卡卡號 | 13–19 碼（含連續無分隔或以空白／連字號分隔），並須通過 Luhn checksum 驗證，過濾一般長數字（如訂單編號） |
| 學號 | 標籤錨定：鄰近出現 `學號／學生證號／student id／student number` 標籤才觸發，後接英數編號 |
| 護照號碼 | 標籤錨定：鄰近出現 `護照／passport` 標籤才觸發，後接 8–9 碼數字 |

**攔截（`block_pii_prompt.py`，UserPromptSubmit）**：使用者送出提示的當下，
對整段 `prompt` 文字逐一比對 `RULES` 中的每個 regex；只要有任一規則命中，
就回傳 `decision: "block"`，整段提示不會送進模型，回饋訊息只列出命中的
規則名稱（如「身分證字號、地址」），**不會把疑似個資的原文回顯**在攔截
訊息裡。因為 Claude Code 的 `UserPromptSubmit` 事件不支援改寫提示內容，
這一層只能整段擋下、無法自動改寫，需使用者自行遮蔽後重新送出。

**去識別化（`redact_sensitive_info.py`，PreToolUse，掛載於 `guard.py`）**：
寫入類工具（`Write`／`Edit`／`MultiEdit`／`NotebookEdit`）即將寫入的內容，
同樣以 `RULES` 逐一比對；命中時**不阻擋**，改用對應的遮罩函式改寫該段文字
後，以 `permissionDecision: "allow"` + `updatedInput` 回傳給 Claude Code，
讓工具改用遮罩後的內容繼續執行原本的寫入。各規則的遮罩方式（保留可辨識
片段、其餘以 `*`／`＊` 取代）：

- 身分證字號：保留首尾字元，中間遮罩，如 `A*******9`
- 手機號碼：保留前 4 碼與後 3 碼，如 `0912***678`
- Email：保留網域與帳號首字元，如 `t***@example.com`
- 地址：保留縣市（與行政區，若有），門牌與路名細節遮罩
- 信用卡卡號：保留前後 4 碼，中間以 `****` 取代，如 `4111 **** **** 1111`
- 學號／護照號碼：保留標籤與編號首字，其餘遮罩，如 `學號 B********`

**學號、護照採「標籤錨定」的理由**：台灣學號無全國統一格式且與身分證字號、
任意編號高度重疊；ROC 護照為純數字且無公開檢查碼。裸偵測會造成大量誤判，
故改為要求鄰近出現標籤關鍵字才觸發，屬精確率優先的取捨，**無法涵蓋無標籤的
裸資料**。信用卡則以 Luhn 驗證取代格式限制，兼顧召回與精確率。擴充或調整
規則一律改 `pii_patterns.py` 的 `RULES`（需要二次驗證時附上驗證函式），兩支
hook 與 `integrated-harness` 會同步取得新規則，不需分別修改。

## 安裝

```bash
# 1. 複製 .claude/ 與 CLAUDE.md 到你的專案根目錄
#    若專案已有 .claude/settings.json 或 CLAUDE.md，請手動合併，勿直接覆蓋
cp -r harness/.claude your-project/
cp harness/CLAUDE.md your-project/     # 若已有，改為合併
chmod +x your-project/.claude/hooks/*.py

# 2. 將 .plan_approved 加入 .gitignore（旗標檔屬本機狀態，不入版控）
echo ".claude/.plan_approved" >> your-project/.gitignore
```

## 計畫核准流程（H 章節的實際操作）

1. Opus 提交執行計畫，此時它只有讀取與分析權
2. 人類審查計畫後，**在自己的終端機**（不是透過 Claude）執行：

   ```bash
   touch .claude/.plan_approved
   ```

3. 核准有效期 60 分鐘（`plan_gate.py` 的 `APPROVAL_TTL_SECONDS`，可調整），
   過期後須重新核准
4. 要立即撤銷核准：

   ```bash
   rm .claude/.plan_approved
   ```

**安全設計**：`plan_gate.py` 會攔截任何指涉旗標檔的操作——含 `.plan_approved`
字樣或以 glob 迂迴指涉 `.claude/` 檔案的 Bash 指令，以及以 Write/Edit 等檔案
工具直接觸碰旗標檔（防止改寫 mtime 延長核准時間窗）。這是本套防線最重要的
反鑽漏洞設計。

## 測試方式（每支 hook 皆可獨立驗證）

Hook 從 stdin 接收 JSON、以 exit code 回應（0 放行、2 攔截），
因此可直接用 echo 模擬：

```bash
# Windows（Git Bash）環境若無 python3，以下命令請改用 python 執行
# 應攔截（exit 2）：未核准的寫入
echo '{"tool_name":"Write","tool_input":{"content":"hi"}}' \
  | python3 .claude/hooks/plan_gate.py; echo "exit=$?"

# 應放行（exit 0）：唯讀指令
echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  | python3 .claude/hooks/plan_gate.py; echo "exit=$?"

# 應攔截（exit 2）：硬寫憑證
echo '{"tool_name":"Write","tool_input":{"content":"password = \"P4ssw0rd88abc\""}}' \
  | python3 .claude/hooks/block_secrets.py; echo "exit=$?"

# 應攔截（exit 2）：危險指令
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /var/www"}}' \
  | python3 .claude/hooks/block_dangerous_commands.py; echo "exit=$?"

# 統一進入點（settings.json 實際掛載的即為 guard.py）
# deny 時輸出 hookSpecificOutput JSON 且 exit 0（stdout 而非 stderr/exit 2）
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /var/www"}}' \
  | python3 .claude/hooks/guard.py; echo "exit=$?"

# 個資去識別化（不阻擋，改寫後放行；stdout 輸出 permissionDecision=allow + updatedInput）
echo '{"tool_name":"Write","tool_input":{"file_path":"note.md","content":"身分證 A123456789"}}' \
  | python3 .claude/hooks/guard.py; echo "exit=$?"
```

部署至團隊共用前，請先在單一專案試行並觀察誤攔截情形，
再合併進團隊層級的 `.claude/settings.json`。

> 本目錄目前沒有自動化測試腳本；上列指令是手動 smoke test。若要使用已整合的
> 自動化回歸測試，請採用 `integrated-harness/tests/`。

## 已知限制（需靠人工補位）

- `plan_gate.py` 的唯讀白名單採保守設計：不在白名單的唯讀指令
  （如 `du`、`ps`）在未核准時也會被攔截。這是刻意取捨——
  寧可多攔，由人類視實際使用情形逐步擴充白名單
- `block_secrets.py` 為樣式比對，無法偵測經過編碼或拆段組合的憑證，
  仍須搭配 SonarQube/SAST 與人工審查
- 危險指令樣式無法窮舉所有變形（如透過腳本檔間接執行），
  hooks 是防線不是保證，E 章節的授權邊界仍是最終依據
- 核准旗標為「時間窗」而非「單一計畫綁定」：60 分鐘內的所有寫入
  都在核准範圍內。若需逐計畫核准，可縮短 TTL 或改為每次施作前
  由人類重新 touch——初期建議先用簡單版，避免過度設計

## 維護

- 新增紅線指令：修改 `block_dangerous_commands.py` 的 `DANGEROUS_PATTERNS`
- 擴充唯讀白名單：修改 `plan_gate.py` 的 `READ_ONLY_COMMAND_PREFIXES`；
  不安全 shell 結構定義於 `UNSAFE_SHELL_PATTERN`（單一規則，勿逐指令列舉）
- 新增憑證樣式：修改 `block_secrets.py` 的 `SECRET_PATTERNS`
- 任何修改後，以上方測試指令回歸驗證放行/攔截行為
- 設計理由、與 `integrated-harness` 同名 hook 的差異，以及修補共用規則時的
  跨產品同步原則，見 [`MAINTENANCE.md`](MAINTENANCE.md)

## 已淘汰的編排提示稿

`fable-orchestrator-prompt.md` 已不再是 Harness 的功能賣點。它僅保留相容性，避免
既有連結突然失效；新專案應直接維護簡短、可稽核的治理政策，內容聚焦於人類授權、
外部副作用、驗收底線與成本門檻，不需教模型如何拆解或路由工作。
