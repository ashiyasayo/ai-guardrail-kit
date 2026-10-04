# Codex hook 格式、沙箱與核准修正

日期：2026-10-04

取代 2026-07-23 dispatcher 邊界筆記中「計畫閘門回傳原生 ask」的假設。
官方 hook 使用 Bash／command，apply_patch 也使用 command；ask 尚未支援，不能
作為核准證據。以共用正規化邊界兼容舊格式；各 slot 保持獨立以保留拒絕與 PII 回寫。

Codex 的核准改成人類終端機建立的 10 分鐘一次性操作憑證，綁定專案、cwd、模式、
輸入、計畫／政策雜湊。保護依賴工作區外 CODEX_HOME 的寫入隔離；hook 無法消耗
憑證時 fail closed，不開放核准庫給模型。這不是遠端簽章核准通道。

計畫草稿移到 `.guardrail/plan/`；strict／standard 允許單獨草稿 patch，變更使既有
核准失配；light 為保留免核准範圍，計畫仍由人類管理。政策與 selector 留在 `.codex/`。
完整操作與影響矩陣見 `docs/codex-hook-compatibility.md`。
