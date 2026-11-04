# Codex 專案護欄目錄統一

日期：2026-11-03

Codex 的專案層 selector、政策、緊急停用檔與拆解文件統一放在
`.codex/guardrail/`。拆解文件的唯一正式路徑是
`.codex/guardrail/plan/decomposition.md`；全域 runtime、loader、核准庫與個人 fallback
仍位於 `$CODEX_HOME/guardrail/`。

只有固定拆解文件具有模型可寫的窄化例外。政策、selector、核准資料及 `.gate_disabled`
仍不可由模型修改；混合計畫與其他目標的 patch 不適用例外。這個判斷順序避免再次形成
「計畫閘門要求寫入，但 `.codex` 通用保護同時禁止寫入」的互斥鎖死。

integrated-harness 的 SessionStart 在新路徑不存在時，會把一般檔案形式的舊版
`.guardrail/plan/decomposition.md` 原子搬移至新路徑；新路徑已存在、舊路徑為符號連結或
不是一般檔案時不覆寫並維持 fail-closed。Claude 的 `.claude/plan/` 與 Copilot 的
`.github/guardrail/plan/` 不受影響。
