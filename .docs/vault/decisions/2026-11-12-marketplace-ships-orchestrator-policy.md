# marketplace 版 integrated-harness 發佈 ORCHESTRATOR.md，子代理協議暫不發佈

日期：2026-11-12

## 決策

- marketplace 版由 SessionStart hook（`inject_protocol.py`）在設定了 `CLAUDE_PLUGIN_ROOT` 時
  注入 plugin 根目錄的 `ORCHESTRATOR.md`；plugin 內的副本須與 `integrated-harness/ORCHESTRATOR.md`
  逐位元組一致（`tests/claude_marketplace_test.sh`）。
- copy-in 版維持以 `CLAUDE.md` 的 `@ORCHESTRATOR.md` 匯入，hook 不注入，避免重複。兩份
  `inject_protocol.py` 仍逐位元組一致，行為差異只來自環境變數。
- `reasoning-protocol-subagent.md` 在 marketplace 版刻意不載入。

## 理由

- marketplace 版沒有 `CLAUDE.md`，原本模型看不到治理政策，兩種安裝型態行為不一致。
- SessionStart 不會對子代理觸發，同一機制送不到子代理。目前沒有已驗證的替代入口
  （未驗證 plugin 是否支援 SubagentStart 類 hook），不承諾功能。
- 主代理一側的委派規則已在主協定「工作技能路由」中約束。

## 代價與限制

- 每個 session 多約 75 行 context，與既有固定提醒部分重複（例如完整照錄核准命令）。
- 未實測注入內容是否有長度上限；只驗證 hook 輸出完整與缺檔時的降級行為。
- 若日後查證 plugin 能為子代理注入 context，可重新評估子代理協議。
