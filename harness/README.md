# Harness — 人類核准與安全 Hook 防線

本目錄是一組可獨立複製到 Claude Code 專案的 PreToolUse hooks。它以人工核准旗標
控制寫入，並另行攔截疑似憑證與高危險 Bash 指令。它也包含一份用來產生
`ORCHESTRATOR.md` 的提示稿，但本目錄本身不是完整的編排層實作。

## 功能與用途分析

| 面向 | 說明 |
| --- | --- |
| 核心功能 | 未取得人類核准時，只允許保守白名單中的唯讀 Bash；一般寫入與其他 Bash 均攔截 |
| 人類控制 | 人類以 `.claude/.plan_approved` 表示核准，旗標預設有效 60 分鐘 |
| 安全防線 | 掃描即將寫入的憑證樣式，並永久攔截毀滅性或高風險 Bash 指令 |
| 主要用途 | 為已有計畫／編排規範的專案補上確定性的施作授權與安全底線 |
| 適用情境 | 需要人工先核准再修改，或要為 orchestrator 與 subagent 套用共同 hook 的團隊專案 |
| 不提供 | 不驗證拆解文件內容、不把核准綁定特定計畫，也沒有可直接載入的完整 `ORCHESTRATOR.md` |

與 `decomposition-gate` 最大差異是：它的 `decomposition_gate.py` 檢查
「拆解是否完成」，本目錄的 `plan_gate.py` 檢查「人類是否核准」。
若兩種條件都需要，應使用 `integrated-harness`，不要把兩支閘門腳本互相混用。

## 檔案職責

| 檔案 | 事件／類型 | 職責 |
| --- | --- | --- |
| `plan_gate.py` | PreToolUse / `Write\|Edit\|MultiEdit\|NotebookEdit\|Bash` | 未經核准攔截寫入性操作；唯讀白名單放行；禁止模型操作核准旗標 |
| `block_secrets.py` | PreToolUse / `Write\|Edit\|MultiEdit` | 攔截疑似 API Key、Token、密碼、私鑰與含密碼的連線字串 |
| `block_dangerous_commands.py` | PreToolUse / `Bash` | 攔截刪除、毀損資料庫、破壞 Git 歷史、停用安全服務等紅線操作 |
| `settings.json` | Claude Code 設定 | 將三支 hook 掛載到對應的 PreToolUse matcher |
| `fable-orchestrator-prompt.md` | 編排規格提示稿 | 引導高階模型產生 A–I 章的 `ORCHESTRATOR.md`；它是生成素材，不是執行時規則 |
| `MAINTENANCE.md` | 維護說明 | 設計理由、與 `integrated-harness` 的差異與跨產品同步原則（維護者閱讀，不需複製到專案） |
| `CLAUDE.md` | 專案指引範本 | 命名規範（識別字英文、註解與回覆用台灣繁體中文）、架構原則（Clean Architecture／SOLID／TDD-BDD、既有系統最小變動）與 Spec by Example（需求以具體範例表達並可轉為可執行測試） |

分工原則：`plan_gate` 管「未核准的一般寫入」；
`block_dangerous_commands` 管「永遠不准模型執行」的紅線。
兩者獨立，互不依賴。

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

## 需要你補充的設定

`fable-orchestrator-prompt.md` 的「團隊環境脈絡」段落內標示
`[在此貼上：...]` 的項目必須由人類填寫，才能請高階模型產生貼合團隊實況的
`ORCHESTRATOR.md`：

- 單位／團隊性質
- 開發技術堆疊（語言、框架、遺留系統與其變動原則、資料庫）
- 基礎設施與維運工具（僅供模型判斷風險等級與派工邊界，
  不建議寫出具體廠商或產品名稱）
- 程式碼與協作規範（架構原則、測試要求、命名慣例、語言慣例等）
- 現有 CLAUDE.md、術語對照表、團隊規範全文
- 過去 AI 協作的失敗案例與踩坑紀錄

留空會讓產出的 `ORCHESTRATOR.md` 過於通用，無法反映團隊實際的風險邊界與
派工判斷準則。
