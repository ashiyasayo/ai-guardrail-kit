# Decomposition Gate — 深廣思考協定的 Claude Code 硬性關卡

將「深廣思考協定」從軟性提示（prompt）升級為 Claude Code 的硬性流程關卡。
在 Claude 完成任務拆解（decomposition）之前，透過 PreToolUse hook 封鎖所有
寫入類工具，強制它「先想清楚、再動手」。

## 功能與用途分析

`decomposition-gate` 是三個目錄中最單純的「任務拆解品質閘門」。它不負責多模型派工、
人工核准或憑證安全，而是確保 Claude 在修改專案前，先留下格式可驗證的拆解文件。

| 面向 | 說明 |
| --- | --- |
| 核心功能 | 檢查 `.claude/plan/decomposition.md` 是否存在，並包含已知資訊、缺少資訊與假設標記 |
| 管制範圍 | Write、Edit、MultiEdit、NotebookEdit，以及可辨識出寫入意圖的 Bash |
| 放行條件 | 拆解文件通過最低格式檢查；唯讀操作及拆解文件本身的建立不受阻擋 |
| 主要用途 | 將「先分析、後實作」從提示文字提升為可執行的 Claude Code PreToolUse 關卡 |
| 適用情境 | 個人開發、教學、PoC，或只想強制留下任務拆解但不需要人工逐次核准的專案 |
| 不提供 | 人類核准、核准期限、憑證掃描、危險命令紅線、subagent 編排與模型路由 |

它屬於「流程紀律」而非「授權控制」：拆解文件可由模型自行完成，通過後便能繼續，
所以不能把它視為人工審批或安全沙箱。需要這些能力時，應使用
`integrated-harness`。

---

## 這個套件解決什麼問題

提示（CLAUDE.md）是「請求」，模型可能因上下文變長、任務看似瑣碎而略過。
Hook 則是「保證」——由 harness 決定是否執行，不交由模型自行選擇。本套件用
PreToolUse hook 把思考協定第一階段（拆解）變成進入實作的必要前置條件。

- 拆解產出物 `.claude/plan/decomposition.md` 不存在或不完整 → 封鎖 Write/Edit/MultiEdit/NotebookEdit
- **Bash 指令具寫入意圖時同樣受管制**（重導向寫檔、rm/mv/cp/mkdir/touch、sed -i）；唯讀 Bash 指令（grep、ls、curl 等）不受影響，Claude 仍能自由蒐集資訊
- 針對 `.claude/plan/` 目錄的操作（含 Bash 複製範本）一律放行，避免「雞生蛋」問題
- 撰寫拆解檔本身一律放行

---

## 目錄結構

```
decomposition-gate/
├── README.md
├── CLAUDE.md                              # 專案指引範本（引用思考協定 + 定義關卡流程）
├── .claude/
│   ├── settings.json                      # PreToolUse hook 設定
│   ├── reasoning-protocol.md              # 深廣思考協定完整版（Opus/Sonnet）
│   ├── reasoning-protocol-subagent.md     # 精簡版（Haiku/subagent）
│   ├── hooks/
│   │   └── decomposition_gate.py           # PreToolUse hook 主程式
│   └── plan/
│       └── decomposition.template.md       # 拆解產出物範本
└── tests/
    └── smoke_test.sh                       # hook 行為驗證（5 情境）
```

---

## 安裝

1. 將 `decomposition-gate/.claude/` 與 `decomposition-gate/CLAUDE.md` 複製到你的專案根目錄。
   若專案已有 `.claude/settings.json` 或 `CLAUDE.md`，請手動合併，勿覆蓋。

   ```bash
   cp -r decomposition-gate/.claude your-project/
   cp decomposition-gate/CLAUDE.md your-project/     # 若已有，改為合併
   ```

2. 確認 hook 有執行權限、且 `python3` 在 PATH 中（Windows 環境無 `python3` 時改用 `python`）：

   ```bash
   chmod +x your-project/.claude/hooks/decomposition_gate.py
   python3 --version
   ```

3. 在 Claude Code 中以 `/hooks` 指令確認 PreToolUse hook 已載入。

---

## 使用流程

1. 開始新任務。Claude 若嘗試修改檔案，會被 deny，並收到提示：
   「請先完成拆解，寫入 `.claude/plan/decomposition.md`」。
2. Claude（或你）複製範本填寫拆解內容：

   ```bash
   cp .claude/plan/decomposition.template.md .claude/plan/decomposition.md
   ```

   填入必要標記：`## 已知資訊`、`## 缺少的資訊`、至少一個 `【假設】`。
3. 拆解完整後，寫入類工具即自動放行，Claude 進入實作。

---

## 設定項（可調整）

以下常數位於 `.claude/hooks/decomposition_gate.py` 檔頭：

| 常數 | 預設值 | 說明 |
| --- | --- | --- |
| `GATE_FILE_RELATIVE_PATH` | `.claude/plan/decomposition.md` | 拆解產出物路徑 |
| `GATE_BYPASS_RELATIVE_PATH` | `.claude/plan/.gate_disabled` | 逃生口檔案，存在時停用關卡 |
| `PLAN_DIR_RELATIVE_PATH` | `.claude/plan/` | 此目錄的操作一律放行 |
| `REQUIRED_MARKERS` | `## 已知資訊` / `## 缺少的資訊` / `【假設】` | 拆解檔必須包含的標記 |
| `GATED_TOOLS` | `Write` / `Edit` / `MultiEdit` / `NotebookEdit` | 受管制的檔案編輯工具 |
| `WRITE_INTENT_PATTERNS` | 3 條規則（見下） | Bash 寫入意圖偵測規則集 |

### Bash 寫入意圖偵測（最小可稽核規則集）

設計原則是**最小可稽核規則**而非窮舉：只涵蓋明確的檔案變更模式，
未匹配者交回正常權限流程裁決。每條規則有名稱，deny 訊息會標明觸發
的規則，便於稽核與除錯。

| 規則名稱 | 偵測內容 |
| --- | --- |
| `redirection` | `>` 與 `>>` 重導向寫檔 |
| `file-mutation` | `rm` / `mv` / `cp` / `mkdir` / `touch`（含 `sudo` 前綴） |
| `sed-in-place` | `sed -i` 就地修改 |

豁免機制只有一處：比對前先移除無害重導向（`>/dev/null`、
`2>/dev/null`、`2>&1` 等 fd 複製）；此外，指令中出現 `.claude/plan/`
路徑者一律放行。

已知限制（刻意的取捨）：本偵測基於 regex 而非完整 shell 解析，
不涵蓋間接寫入路徑（例如 `tee`、`chmod`、`python -c` 內嵌寫檔、
指令替換 `$( )`）。decomposition gate 的目的是流程引導而非安全邊界——
安全封鎖請交由你既有的 dangerous command blocking hook 負責，
兩者關注點不同、可並存。若日後從 hook 日誌觀察到特定繞過路徑
頻繁出現，再逐條加入規則即可，勿預先枚舉。

### 緊急停用關卡

建立逃生口檔案即可暫時放行所有寫入：

```bash
touch .claude/plan/.gate_disabled
# 完成緊急修復後移除
rm .claude/plan/.gate_disabled
```

---

## 運作原理（技術依據）

- **決策格式**：PreToolUse 使用 `hookSpecificOutput.permissionDecision`
  （值為 `allow` / `deny` / `ask`）搭配 `permissionDecisionReason`。
  舊版頂層 `decision`/`reason` 欄位已對此事件棄用，故本套件採新格式。
- **退出碼**：本 hook 一律以 exit 0 搭配 JSON 輸出進行決策，而非 exit 2。
  好處是 deny 的 reason 會結構化回饋給 Claude，引導它去補齊拆解檔，
  形成自我修正迴圈。
- **關卡通過時不強制 allow**：通過檢查後 hook 以 exit 0 且無輸出結束，
  交回 Claude Code 正常權限流程裁決。這是為了不覆蓋你既有的 permissions
  設定（例如 secret 路徑保護）——hook 的 allow 只能略過提示，無法放寬
  settings 中的 deny 規則。
- **強制力**：PreToolUse 的 deny 在 bypassPermissions 模式與
  `--dangerously-skip-permissions` 下仍然生效；hook 只能收緊政策、不能弱化。

> Hooks API 演進速度快，事件與欄位可能隨版本變動。部署前請以官方
> hooks reference 為準，並用 `/hooks` 確認實際載入狀態。

---

## 與其他 hook 共存

本 hook 與 secret blocking、dangerous command blocking 等既有 PreToolUse hook
互不衝突——多個 hook 可並存於同一 matcher 下並行執行，且任一 hook 的 deny
即足以封鎖。分工建議：dangerous command hook 負責「永遠不該執行的指令」
（安全邊界），本 decomposition gate 負責「拆解完成前不該執行的寫入」（流程關卡）。

---

## 測試

```bash
bash tests/smoke_test.sh
```

涵蓋 12 個情境：檔案編輯工具 5 項（唯讀放行、無拆解檔封鎖、拆解檔本身
放行、關卡通過放行、缺標記封鎖）＋ Bash 偵測 7 項（唯讀放行、/dev/null
豁免、重導向封鎖、rm 封鎖、sed -i 封鎖、plan 目錄放行、關卡通過後放行）。
全部通過才會回傳 exit 0。

---

## 授權與注意事項

- Hook 以你的終端機權限執行任意程式碼。套用前請自行審閱程式碼內容。
- 請務必先於測試專案驗證，再套用到正式工作流。
- 本套件僅為流程輔助，不能取代模型本身的能力上限；它改變的是「思考路徑的
  形狀與強制性」，而非增加模型的原生推理深度。
