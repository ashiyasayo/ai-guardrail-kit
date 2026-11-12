# marketplace 版 integrated-harness 發佈 ORCHESTRATOR.md 與子代理協議

日期：2026-11-12

## 決策

- marketplace 版由 SessionStart hook（`inject_protocol.py`）在設定了 `CLAUDE_PLUGIN_ROOT` 時
  注入 plugin 根目錄的 `ORCHESTRATOR.md`；plugin 內的副本須與 `integrated-harness/ORCHESTRATOR.md`
  逐位元組一致（`tests/claude_marketplace_test.sh`）。
- copy-in 版維持以 `CLAUDE.md` 的 `@ORCHESTRATOR.md` 匯入，hook 不注入，避免重複。兩份
  `inject_protocol.py` 仍逐位元組一致，行為差異只來自環境變數。
- `reasoning-protocol-subagent.md` 在 marketplace 版最初刻意不載入；此項已被取代，
  改由 `SubagentStart` hook 注入（見文末「後續更新」）。

## 理由

- marketplace 版沒有 `CLAUDE.md`，原本模型看不到治理政策，兩種安裝型態行為不一致。
- SessionStart 不會對子代理觸發，同一機制送不到子代理。目前沒有已驗證的替代入口
  （未驗證 plugin 是否支援 SubagentStart 類 hook），不承諾功能。
- 主代理一側的委派規則已在主協定「工作技能路由」中約束。

## 代價與限制

- 每個 session 多約 75 行 context，與既有固定提醒部分重複（例如完整照錄核准命令）。
- 未實測注入內容是否有長度上限；只驗證 hook 輸出完整與缺檔時的降級行為。
- 若日後查證 plugin 能為子代理注入 context，可重新評估子代理協議。

## 查證結果（2026-11-12，官方 hooks 參考頁）

- 有 `SubagentStart` 事件：Agent 工具啟動、恢復子代理時觸發，可用 agent type 做 matcher；
  hook 不能阻擋建立，但可回傳 `hookSpecificOutput.additionalContext`，文件原文為
  「String added to the subagent's context at the start of its conversation, before its first
  prompt」。支援 command hook。已對照保存的文件原文核對。
- plugin 的 `hooks/hooks.json` 可註冊 hook，格式同 settings.json；plugin 子代理的 agent type 為
  `plugin名:agent名`，matcher 須以 `^…$` 錨定。此點來自 plugins 元件頁的摘錄，**未逐字核對原文**。
- 版本需求：文件未載。本機 Claude Code 版本未確認。
- 更正：上文「SessionStart 不會對子代理觸發」是推論，文件**沒有**明說，不得當成事實。
  理由改為：即使 SessionStart 是否在子代理觸發不明，`SubagentStart` 才是文件明載的子代理注入入口。
- 結論：載入子代理協議的前提（有入口）已成立，已實作：plugin 0.9.4 新增 `SubagentStart` hook
  （`inject_subagent_protocol.py`），不設 matcher，copy-in 不註冊。缺檔時不輸出並正常結束。
  實際環境的注入行為屬文件外驗證，當時尚未實測（已於下節驗證）。

## 後續更新（v0.15.0）

- PR #55 合併，plugin 0.9.4 隨 v0.15.0（2026-11-12）發版，marketplace 版正式發佈子代理協議。
- 人工驗證（真實 Claude Code 環境）：子代理自述其 context 內有該協定，引用內容與
  `reasoning-protocol-subagent.md` 相符；主代理 context 沒有。這是子代理自述，沒有 debug log 佐證。
- 仍未確認：`SubagentStart` 的版本需求（官方文件未載）、SessionStart 是否在子代理觸發（文件未明說）。
