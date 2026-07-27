# 版本與發布策略

本檔是 ai-guardrail-kit 版本語意的**單一事實來源**。README、CHANGELOG 與各平台
文件若與本檔敘述衝突，以本檔為準。

## 一句話

**Git tag `vX.Y.Z` 是本專案唯一的發布座標**，涵蓋 Claude、Codex、GitHub Copilot
三個平台。Claude plugin 的 `plugin.json` 版號是平台介面欄位，**不是** repo 版本。

---

## 為什麼發布座標是 tag，不是各 plugin 版號

1. **消費單位就是整個 repo 的一個 ref。** Codex 以
   `codex plugin marketplace add ... --ref <ref> --sparse` 註冊、Claude marketplace
   走預設分支、Copilot 直接複製 `copilot/plugins/` 下的檔案。三種安裝機制都**無法**
   只取用某個 plugin 的某個版本，因此獨立的 per-plugin 版本線在消費端不可解析。
2. **這些 plugin 不是可自由組合的套件，而是同一產品的互斥變體。** 它們共用
   `shared/codex/`、`shared/claude/` 單一來源，並由逐位元組同步測試守護。
   「harness 搭配哪一版 shared」這種問題只有「同一個 commit 快照」答得出來。
3. 承 1、2，multi-tag monorepo（`claude-harness/v0.6.0` 之類）在此專案是假精度：
   維護成本乘上單位數，而使用者拿不到對應的收益。

---

## 各平台的版號載體差異（重要）

三個平台的 plugin 格式不同，能承載版號的欄位也不同：

| 平台 | 版號載體 | 說明 |
| --- | --- | --- |
| Claude Code | `claude/plugins/<mode>/.claude-plugin/plugin.json` 的 `version` | Claude plugin 介面欄位，會被平台讀取顯示，**必須維護** |
| Codex | **無** | Codex plugin 目錄僅含 `hooks/`、`skills/` 等內容，格式中沒有版號欄位 |
| GitHub Copilot (VS Code) | **無** | Agent hooks (Preview) 設定為 `.github/hooks/*.json`，格式中沒有版號欄位 |

**本專案不為 Codex／Copilot 另外發明版號檔案。** 憑空加一個 `VERSION` 純文字檔
會製造第二套沒有任何平台會讀取、也沒有任何機制強制同步的「真相來源」，只會漂移。
這兩個平台的版本一律以 repo tag 指稱。

### 誠實聲明：早期 CHANGELOG 中的 Codex／Copilot 版號不具查證性

`0.1.0` 之前的 CHANGELOG 條目曾為 Codex 與 Copilot 的 plugin 敘述過版號
（例如「Copilot `decomposition-gate` 初始版號 `0.1.0`」）。這些數字**沒有任何檔案
承載**，使用者安裝後無從查證。既有條目作為歷史記錄予以保留、不回頭改寫，但自
`0.1.0` 起 CHANGELOG **不再為 Codex／Copilot plugin 宣稱版號**。

---

## repo tag 的 SemVer 語意

tag 格式為 `vX.Y.Z`（annotated tag），版號遞增的判準是**消費者可感知的相容性**：

| 層級 | 觸發條件 | 例子 |
| --- | --- | --- |
| MAJOR | 需要人工遷移才能升級 | 設定檔格式變更、拆解檔路徑改名、指令改名、hook 決策語意反轉（原本放行改為封鎖） |
| MINOR | 向下相容的能力新增 | 新增一種模式、新增一個平台、新增一項檢查規則 |
| PATCH | 不改變介面的修正 | 修 bug、補測試、文件修訂、誤判率調整 |

判準看的是**使用者端**：hook 內部重構若不改變任何對外可觀察行為，屬 PATCH。

### `0.x` 代表 Preview，不承諾相容性

目前處於 `0.x`，明示本專案尚未穩定：

- GitHub Copilot 側依賴 VS Code Agent hooks，該 API 仍為 **Preview**，可能變更。
- Copilot 的 macOS／Linux 啟動器**尚未實機驗證**。
- Claude 與 Codex 的核准、生命週期語意不同，跨平台差異尚未完整文件化。

`0.x` 期間，MINOR 遞增即可含破壞性變更（符合 SemVer 對 `0.y.z` 的規定），
但仍會在 CHANGELOG 明確標示。

### 升上 `1.0.0` 的條件（先寫死，避免永遠停在 0.x）

三項全部成立才發 `1.0.0`：

1. VS Code Agent hooks 脫離 Preview，且本專案已跟進其正式版介面。
2. Copilot 的 macOS／Linux 路徑完成實機驗證（不再帶「未驗」註記）。
3. 三平台的決策語意差異（核准、fail-open／fail-closed、管制工具清單）完成
   對照文件化。

---

## Claude plugin 版號的定位

`claude/plugins/<mode>/.claude-plugin/plugin.json` 的 `version` 表示**該模式自身
的行為版本**——這個模式的邏輯改過幾次。它：

- **會**在該模式的 hook 行為、管制範圍或檢查規則變更時遞增；
- **不會**因為其他模式或其他平台的變更而遞增；
- **不需要**、也**不應該**與 repo tag 對齊。使用者看到 `harness 0.6.0` 時，那不是
  repo 的版本。

四種模式各自獨立遞增，出現不同數字是正常的。

---

## CHANGELOG 慣例

- 單一檔案 `CHANGELOG.md`，格式沿用 Keep a Changelog 風格
  （`### Added` / `### Changed` / `### Fixed` / `### Security`）。
- 開發期間條目寫在 `## [Unreleased]`。
- 發版時把 `## [Unreleased]` 改為 `## [X.Y.Z] - YYYY-MM-DD`，並在上方補一個新的
  空 `## [Unreleased]`。
- 條目繼續依「哪個平台的哪個模式」敘述變更，方便使用者定位；但版號只出現在
  Claude plugin 的情境（見上節）。

---

## 發版流程

`main` 受 ruleset 保護，禁止直接 push，因此發版分兩段：

```bash
# 1. 在 feature 分支定版 CHANGELOG，走 PR 合併進 main
git switch -c docs/release-x-y-z
# 編輯 CHANGELOG.md：[Unreleased] -> [X.Y.Z] - YYYY-MM-DD，補新的空 [Unreleased]
gh pr create --base main
# CI 的 tests 檢查綠燈後合併

# 2. 在合併後的 main 打 tag 並建立 Release
git switch main && git pull
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z --title "vX.Y.Z" --notes "<貼上該版 CHANGELOG 段落>"
```

本專案是純原始碼 repo，Release 不附加建置產物。

> **tag 是對外不可逆的動作。** 一旦公開，已釘版的使用者會依賴它；刪除 tag 或
> Release 會破壞他們的安裝。發版前務必確認 CHANGELOG 已定稿。

---

## 使用者如何釘版本

| 需求 | 做法 |
| --- | --- |
| 求穩定、可重現 | 指向 tag：`--ref v0.1.0` |
| 求最新 | 指向主幹：`--ref main` |

Codex 範例：

```bash
codex plugin marketplace add https://github.com/ashiyasayo/ai-guardrail-kit.git \
  --ref v0.1.0 --sparse .agents --sparse codex/plugins
```

Claude Code 側，**已查證**`claude plugin marketplace add`
不提供指定 ref／tag 的能力（`claude plugin marketplace add --help` 未列出對應參數），
只能取得預設分支（`main`）最新內容。2026-07-27 已對 GitHub 遠端來源實機驗證：
註冊、`claude plugin marketplace update` 刷新快取、`claude plugin install
decomposition-gate@ai-guardrail-kit` 安裝，快取版本正確讀出 `0.2.0`、6 個檔案與
執行權限位（`100755`）均與 repo 逐位元組一致，過程未見任何釘版選項。因此
Claude 側需要固定版本時，請 clone 指定 tag 後以 copy-in 方式安裝
（見 README「copy-in 安裝」）：

```bash
git clone --depth 1 --branch v0.1.0 https://github.com/ashiyasayo/ai-guardrail-kit.git
```

Copilot 為手動複製檔案，同樣從上述指定 tag 的原始碼取檔。

---

## 相關

- 分支模型與保護設定：`.docs/vault/decisions/2026-07-27-publishing-and-branch-protection-model.md`
- 本策略的決策紀錄：`.docs/vault/decisions/2026-07-27-versioning-and-release-strategy.md`
