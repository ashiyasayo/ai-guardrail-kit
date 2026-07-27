# 版本與發布策略：repo tag 為唯一發布座標

日期：2026-07-27

一句話摘要：發布座標統一為 repo 的 Git tag `vX.Y.Z`；只有 Claude plugin 保留
`plugin.json` 版號（代表該模式自身行為版本，不等於 repo 版本），Codex／Copilot
不另建版號檔案；規則落在 `VERSIONING.md`，首個標記版本為 `v0.1.0`（Preview）。

## 背景

採 GitHub Flow（見 [[2026-07-27-publishing-and-branch-protection-model]]）後，
「正式版本以 tag 標記」已定案，但 tag 與既有 plugin 版號的關係未定義，因此延後
發首版。本次補上這個定義。

## 盤點發現（推翻了原本的假設）

原以為三平台的 8 個 plugin 各自有版號、需要決定要不要對齊。實際盤點結果：

| 平台 | 版號載體 | 現值 |
| --- | --- | --- |
| Claude ×4 | `.claude-plugin/plugin.json` 的 `version` | `decomposition-gate 0.2.0`、`sensitive-data-guard 0.1.2`、`harness 0.6.0`、`integrated-harness 0.5.0` |
| Codex ×4 | **無**（目錄僅 `hooks/`、`skills/`；`integrated-harness` 另有 `orchestration-policy.md`、`README.md`） | — |
| Copilot ×1 | **無**（`hooks/`、`plan/`、`tests/`、`README.md`） | — |

也就是 9 個單位裡有 5 個**連版號欄位都不存在**。而 CHANGELOG 曾為 Codex／Copilot
的 plugin 敘述過版號（例如「Copilot `decomposition-gate` 初始版號 `0.1.0`」），那些
數字沒有任何檔案承載，使用者安裝後無從查證——屬**無載體的假版號**。

## 決策

1. **repo tag `vX.Y.Z` 為唯一發布座標**，涵蓋三平台。
2. **Claude 的 `plugin.json` version 保留**：它是 Claude plugin 介面欄位、會被平台
   顯示，不能空著。定位為「該模式自身的行為版本」，明文宣告不等於 repo 版本，
   四種模式各自獨立遞增。
3. **不為 Codex／Copilot 引入版號欄位**（例如 `VERSION` 純文字檔）。這兩個平台的
   格式沒有版號概念，硬加會產生無平台讀取、無機制強制同步的第二套真相來源，
   必然漂移。它們的版本一律以 repo tag 指稱。
4. **CHANGELOG 自 `0.1.0` 起不再為 Codex／Copilot 宣稱版號**；既有條目作為歷史
   記錄保留、不回頭改寫，但在 `0.1.0` 節首與 `VERSIONING.md` 明白聲明其不具查證性。
5. **`0.1.0` 為首個標記版本**，`0.x` 明示 Preview、不承諾相容性。升 `1.0.0` 的三個
   條件先寫死於 `VERSIONING.md`（VS Code Agent hooks 脫離 Preview、Copilot
   macOS／Linux 實機驗證、三平台語意差異文件化），避免永遠停在 0.x。

## 為何不採 monorepo 多 tag（`claude-harness/v0.6.0` 之類）

- **消費單位是整個 repo 的一個 ref**：Codex `--ref <ref> --sparse`、Claude
  marketplace 走預設分支、Copilot 手動複製檔案——三種機制都無法只取用某個 plugin
  的某個版本，per-plugin 版本線在消費端不可解析，是假精度。
- **這些 plugin 是同一產品的互斥變體，不是可組合套件**：共用 `shared/codex/`、
  `shared/claude/` 單一來源並由逐位元組同步測試守護。「harness 搭配哪一版 shared」
  只有「同一 commit 快照」答得出來。
- 維護成本乘上單位數，使用者得不到對應收益。

## 未查證事項（誠實標記）

`claude plugin marketplace add` 是否支援指定 ref／tag，**未查證**。本專案文件記載
的註冊指令未帶 ref，實際取得預設分支內容。因此 Claude 側的釘版寫法一律建議
`git clone --branch <tag>` 後 copy-in，不假設 CLI 有釘版能力。

## 影響範圍

新增 `VERSIONING.md`（規則單一事實來源）；`CHANGELOG.md` 定版並補連結區；
`README.md`（新增「版本與發布」章節與 `--ref` 釘版說明）、`CLI_REFERENCE.md`
（釘版與發版指令）、`ARCHITECTURE.md`（版號載體不對稱）、`docs/codex-marketplace.md`
（`--ref` 釘 tag）同步。未觸碰任何 hook 程式碼。

## 關聯

- [[2026-07-27-publishing-and-branch-protection-model]]（GitHub Flow 與 main 保護）
- [[2026-07-23-copilot-vscode-support-plan]]（Copilot 為何仍屬 Preview）
