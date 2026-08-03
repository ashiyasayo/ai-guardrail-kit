# Copilot sensitive-data-guard 批次的三項收尾待辦

日期：2026-08-03（狀態同日更新）

一句話摘要：Copilot `sensitive-data-guard` 移植已完成並通過全部 18 支回歸測試，
但留下三項追蹤事項。共通樣式是：**測試證明了實作，沒證明前提。**

| 項 | 主題 | 狀態 |
| --- | --- | --- |
| 1 | `UserPromptSubmit` 輸出形狀 | 未實機驗證，待處理 |
| 2 | Claude／Codex 測試稽核 | 已稽核：路徑問題不適用；斷言問題確認成立，正在修 |
| 3 | 排程豁免的環境變數 | 已緩解（改用 `standard` 政策），判定條件仍未修好 |

三者都不阻擋目前發布，但都不該被「全綠」掩蓋。待辦 2 與 3 都已有部分結論，
**但兩項的核心問題都還沒關閉**——詳見各節。

## 待辦 1：`UserPromptSubmit` 輸出形狀尚未實機驗證

`copilot/plugins/sensitive-data-guard` 的提示詞個資阻擋
（`block_pii_prompt.py` → `hook_protocol.block_prompt()`）輸出形狀是依 `PreToolUse`
的已驗格式**類推**實作，尚未在 VS Code 實機確認。程式碼與 smoke test 皆已標
【未實機驗證】。

**為何重要：** VS Code Agent hooks 仍是 Preview，非 JSON 或形狀不符的輸出會被判
`NonBlockingError` 而 **fail-open**（放行）。若 `UserPromptSubmit` 的實際契約與
`PreToolUse` 不同，這道防線會在**完全沒有錯誤訊息**的情況下失效。smoke test 只能
驗證我們自己輸出的形狀前後一致，無法驗證 VS Code 是否接受它——這是測試能力的邊界，
不是測試寫得不夠好。

**如何驗證：** 在 VS Code 實機安裝該模式，送出含個資的提示詞，確認真的被阻擋而非
靜默放行。驗證後同步更新四處標註：

1. `hook_protocol.block_prompt()` 的註解
2. `copilot/plugins/sensitive-data-guard/tests/smoke_test.sh` 的段落標題
   （目前寫「輸出形狀未實機驗證」）
3. `README.md`
4. `ARCHITECTURE.md`

背景見 [[2026-07-31-copilot-sensitive-data-guard]] 與
[[2026-07-23-vscode-copilot-hook-wiring]]（fail-open 鐵律）。

## 待辦 2：Claude／Codex 測試稽核（已完成，兩個查核點結論不同）

Copilot smoke test 的 Windows 假性通過已修復，當時刻意未擴大檢查範圍到 Claude 與
Codex 的測試。**稽核已於 2026-08-03 完成**，兩個查核點結論分歧：

| 查核點 | 結論 |
| --- | --- |
| POSIX 臨時路徑經 stdin | **不適用**。Claude／Codex 測試使用 Python `tempfile.TemporaryDirectory()` ＋進程內 `subprocess.run(input=...)`，不經 Git Bash 的原生執行檔通道，不構成同一根因鏈。 |
| 「應被 deny」斷言只比對 `deny` | **確認成立**。`tests/claude_guardrail_test.sh` 的 `assert_denied()` 只檢查 `result[0] == 2 or result[1] == "deny"`；`tests/codex_guardrail_test.sh` 多處 `denied()` 呼叫未接住回傳的 reason。已有獨立拆解在處理。 |

值得記下的是這兩點的關係：**當初把它們綁成一項是對的判斷**。若只查路徑問題，
會因為「不適用」而收工，漏掉真正存在的斷言問題——而斷言問題才是讓缺陷長期隱形的
那一半。下面「如何著手」保留原始的兩點檢查清單，因為它正是這次能查出東西的原因。

**為何重要：** 根因是 Git Bash 只改寫傳給原生執行檔的**參數**，不改寫經 **stdin**
傳入的內容。任何把 `mktemp -d` 的 POSIX 路徑放進 JSON 事件、再經 stdin 餵給原生
Windows Python 的測試都會中同一個坑。危險的不是失敗，而是**假性通過**：路徑解析
失敗造成普遍性 deny，只比對 `"permissionDecision": "deny"` 的寬鬆斷言照樣是綠的
——即使受測邏輯完全失效。Copilot 那次同時有 6 個真失敗與 7 個假成功，後者更危險。

**如何著手：** 稽核時兩件事必須一起查，不能只看有沒有 FAIL：

1. `cwd`／路徑是否經 `cygpath -w` 轉換並轉義反斜線。
2. 所有「應被 deny」的斷言是否比對**原因專屬的 ASCII 片段**（`Plan gate:`、
   `.gate_disabled`、`Secret blocked`、`Personal data blocked`、
   `Invalid Copilot hook input`），而非只比對 `deny`。hook 輸出是 ASCII 轉義 JSON，
   中文原因會變成 `\uXXXX`，故必須挑 ASCII 片段。

全 18 支測試在本機皆通過，因此這項稽核的價值正是找出被掩蓋的失敗——
**不要因為「全綠」就判定沒事**，那正是 Copilot 那次長期無人察覺的原因。
本次結果證實了這點：測試全綠，斷言問題依然存在。

完整根因與診斷時踩到的二次陷阱（換通道驗證等於換掉受測條件）見
[[2026-07-31-git-bash-posix-path-via-stdin]]，其「適用範圍」段落已預先標記本項。

## 待辦 3：排程豁免依賴的環境變數，實測並不存在（已緩解，未根治）

**現況（2026-08-03）：** CoWork 專案已在其 `.claude/orchestration-policy.md` 設
`- Approval Mode: standard`，排程確認可正常執行。這是下方「如何著手」第 2 點的
合法出口，**不是修好判定條件**——`guard.py` 的排程豁免依然從未生效，任何仍在
`strict` 下的無人排程都會遇到同一個死結。本項因此保持開放。

`claude/plugins/{harness,integrated-harness}/hooks/guard.py:48` 以
`os.environ.get("CLAUDE_SCHEDULED_TASK") == "1"` 判定排程任務，命中時豁免
`plan_gate`（`block_dangerous_commands` 與 `block_secrets` 仍執行）。

**實測結果（2026-08-03，範圍僅限 Claude CoWork 排程）：該變數為 `None`。**
以 hook 探針寫檔取樣，兩次排程執行皆為 `None`。因此豁免條件從未成立，`plan_gate`
在無人可核准的環境仍要求核准，排程任務直接卡死。已排除「安裝版本過舊」——
plugin cache 的 `0.6.1` 與 `0.6.0` 都含此豁免碼。

**未驗證：** Claude Code 自身的排程功能是否會設此變數，本次沒有測，不可外推。
正確的排程辨識訊號是什麼，目前仍未知。

**為何重要：** 這不只是一個沒生效的旗標。strict 模式的核准綁計畫 SHA-256 且只有
60 分鐘 TTL，本質上就無法在無人排程中滿足——豁免是唯一出口，出口失效就等於
`integrated-harness` 與無人排程完全不相容。

更值得注意的是 `tests/claude_guard_test.sh` **是綠的**。它以 `extra_env` 人工注入
`CLAUDE_SCHEDULED_TASK="1"`，驗證「若變數為 1 則豁免」——實作正確無誤，但
「排程時變數真的會是 1」這個前提從未被驗證。這與待辦 2 是同一類缺陷：
**測試證明了實作，沒證明前提。** 這類缺陷不會讓測試變紅，所以只能靠實機觀察發現。

**如何著手：**

1. 先在排程環境 dump 環境變數，找出實際可辨識排程身分的訊號，再決定判定條件該
   怎麼寫。**不要在取得這項證據前就放寬 `guard.py`**——那會影響所有專案的人類
   授權關卡，為單一排程情境動全域防線，代價不對稱。
2. 若只是要讓某個排程任務能跑，已有不需改碼的合法出口：該專案的
   `.claude/orchestration-policy.md` 設 `- Approval Mode: standard`。
   `plan_gate.py:323` 會跳過核准檢查，但仍強制拆解必要標記（`:239`）與允許修改
   範圍（`:321`），拿掉的恰好只有「人類在場按核准」這一項。
3. 修法確定後，測試要補的不是既有案例，而是「前提是否成立」這一層——
   但那需要先知道正確訊號，故順序不能顛倒。

**診斷方法論提醒：** 本次我最初把探針掛在 `SessionStart`，而 `guard.py` 實際掛在
`PreToolUse`。`SessionStart` 沒觸發並不代表 `PreToolUse` 沒觸發，以前者結果推斷
後者是**換通道推論**，會得出相反結論（我當時確實據此誤判為「排程未載入 hook」）。
改用 `PreToolUse` 探針後才取得可歸屬的證據。這與
[[2026-07-31-git-bash-posix-path-via-stdin]] 的教訓完全一致：
**驗證某條通道的行為時，探針必須走同一條通道。**
