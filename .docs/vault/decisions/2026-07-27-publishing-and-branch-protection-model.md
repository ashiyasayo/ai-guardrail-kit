# 發布與分支保護模型：GitHub Flow（main 主幹 + tag 發布）

日期：2026-07-27

一句話摘要：採 GitHub Flow——單一受保護主幹 `main`、feature → PR → `main`、CI(`tests`)
為合併門檻、正式版本以 `git tag` + GitHub Release 標記；曾短暫評估過「`release` 分支
為正式版」方案，因命名與載體不符慣例而放棄。

## 背景與最終決策

先前只有 `main` 一條分支、無 CI、無分支保護。目標是「有一個受保護、CI 把關的正式
發布來源」。**最終採 GitHub Flow**：

- **`main` 為唯一長期主幹**，並為 GitHub 預設分支。
- **分支保護（ruleset `main-protection`，id 19781358，綁 `refs/heads/main`）**：
  - `deletion`（禁刪）、`non_fast_forward`（禁 force push）
  - `pull_request`（一律走 PR；`required_approving_review_count = 0` → 單人可自 PR 自合，
    但仍強制 PR + 禁直接 push；`dismiss_stale_reviews_on_push = true`）
  - `required_status_checks`（`strict`，必要檢查 `tests`；CI 不過不能合併）
- **CI**（`.github/workflows/ci.yml`）：`main` 的 push/PR 執行 `tests/run_all.sh` ＋
  `copilot/plugins/decomposition-gate/tests/smoke_test.sh`。
- **正式版本以 tag 標記**：`git tag -a vX.Y.Z` + `gh release create`；版本是時間點快照，
  非移動分支。
- **消費者安裝來源**：Codex `--ref main`（最新穩定）或 `--ref <tag>`（釘版本）；
  Claude 走預設分支 `main`。

## 日常開發流程

1. 從 `main` 開 feature 分支（`feat/*`／`fix/*`／`docs/*`）。
2. 開發 + 本地 `bash tests/run_all.sh`；模型端照舊走拆解閘門與人類核准。
3. push → 開 PR（base `main`）→ CI `tests` 綠燈 → squash merge → 刪分支。
4. `main` 永遠維持可發布狀態。
5. 到穩定點才發版：打 tag + GitHub Release，CHANGELOG `[Unreleased]` 定版。

## 為何放棄「release 分支為正式版」方案（誠實記錄演進）

實作過程中曾短暫建立 `release` 分支當正式版並設為預設分支。後檢討發現不符 git/GitHub
慣例而回退：

- `release` 在 Git Flow 有既定語意（**短期**發布準備分支或 `release/x.y` 維護分支），
  不是長期主幹；把唯一主幹命名為 `release` 會造成語意混淆。長期主幹慣例名為 `main`。
- 「正式版本」的正規載體是 **tag/Release**（時間點快照），而非一條持續移動的分支。
- 回退動作：`main` 同步 `release` 內容 → 預設分支改回 `main` → ruleset 由
  `release-protection` 改為 `main-protection`（綁 `main`）→ `--ref` 改回 `main` →
  刪除 `release` 分支。

## exec-bit 根治（CI 首次揭發的既有 bug）

導入 CI 後，真 Linux 環境**首次**揭發：一批既有檔案在 git 記錄為 `100644`（無 exec bit），
本地 WSL 因 `core.fileMode=false` 未比對而長期未發現（見
[[2026-07-23-wsl-core-filemode-exec-bit]]）。

- **症狀**：`codex_global_install_test`（`scripts/... Permission denied`）與
  `codex_mode_switch_test`（`verify-codex-mode` 的 `[[ -x ]]` 檢查）。
- **判準**：只對「被 `[[ -x ]]` 檢查的 Codex PreToolUse 進入點」「被直接執行的 script」
  「跨平台進入點一致」補 `100755`；**import-only 模組**（`hook_protocol`／`pii_patterns`／
  `security_checks`）與**以 `python3` 呼叫的 Claude hooks** 維持 `100644`。
- **範圍**：11 檔（scripts×2、codex `security_guard.py`／`pii_guard.py`／SDG
  `block_secrets.py`、copilot `decomposition_gate.py`、`shared/codex` 來源×2），維持
  `shared/codex` 來源與 plugin 副本 mode 一致（`cp -p` sync）。純 mode 變更。

## 維運附註（gate 誤傷）

user-level plan_gate 的「核准旗標保護」會攔截**任何指令字串含 `.plan_approved`**（含唯讀
命令與清理誤產生的 `.claude/.plan_approved!` 垃圾檔）——需在系統終端機處理。屬既有保護
的預期副作用，非缺陷。

## 關聯
- [[2026-07-23-copilot-vscode-support-plan]]（Copilot decomposition-gate Phase 1）
- [[2026-07-23-wsl-core-filemode-exec-bit]]（exec-bit 漂移的根因 gotcha）
