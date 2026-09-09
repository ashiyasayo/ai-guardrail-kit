# Codex 一鍵解除安裝邊界

日期：2026-09-09

## 決策

新增 `uninstall-codex-guardrail`，由已部署的 Codex runtime manager 執行。未帶
`--confirm` 時只列出受管 selector；確認後才移除 registry 記錄的 project/local
selector、固定位置的 user fallback、loader plugin、受管 hooks 與 marketplace。

## 理由

project selector 位於專案可寫目錄，不能靠掃描或路徑猜測批次刪除。只採用
`$CODEX_HOME/guardrail/selector-index.json` 的受管紀錄，並重新驗證每個路徑與 scope
對應關係，才能限制刪除範圍。個人 policy 與 unrelated hooks 不屬本產品所有權，永遠保留。

## 限制

`--prune-cache` 必須明確指定，才會清除未引用 runtime cache。marketplace 移除失敗時，
loader 已移除的狀態不回復，避免重建指向不存在 runtime 的 selector；命令會明確回報
部分完成，使用者可單獨重試 marketplace 移除。
