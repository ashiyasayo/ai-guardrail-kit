# 正式發布改用 release 分支：分支保護、CI 與消費者安裝來源

日期：2026-07-27

一句話摘要：`release` 成為正式發布分支（受 ruleset 保護 + CI 門檻 + GitHub 預設分支），
Codex 消費者釘 `--ref release`、Claude 消費者走預設分支；並在導入 CI 時一併根治了
repo 長期潛藏的 git exec-bit 漂移。

## 背景與決策

先前只有 `main` 一條分支、無 CI、無分支保護。決定改為「`release` 為正式發布版」，
讓對外安裝來源與可合併門檻明確化。

**決策**：
- **`release` 為正式發布分支**，並設為 GitHub **預設分支**。
- **分支保護（ruleset `release-protection`，id 19781358）**：
  - `deletion`（禁刪分支）、`non_fast_forward`（禁 force push）
  - `pull_request`（一律走 PR；`required_approving_review_count = 0`，單人可自 PR 自合、
    但仍強制 PR + 禁直接 push；`dismiss_stale_reviews_on_push = true`）
  - `required_status_checks`（`strict` 政策，必要檢查 `tests`；CI 不過不能合併）
- **CI**（`.github/workflows/ci.yml`）：於 `main`／`release` 的 push/PR 執行
  `tests/run_all.sh`（全平台全模式回歸）＋ `copilot/plugins/decomposition-gate/tests/smoke_test.sh`。
- **消費者安裝來源**：
  - Codex：`--ref release`（README 與 `docs/codex-marketplace.md` 已改）→ 永遠拿正式版。
  - Claude：`claude plugin marketplace add` 無 `--ref` 參數 → 走 repo 預設分支；
    因預設分支已設為 `release`，Claude 消費者亦自動取得正式版。

## exec-bit 根治（CI 首次揭發的既有 bug）

導入 CI 後，真 Linux 環境**首次**揭發：一批既有檔案在 git 記錄為 `100644`（無 exec bit），
本地 WSL 因 `core.fileMode=false` 未比對權限而長期未發現（見
[[2026-07-23-wsl-core-filemode-exec-bit]]）。

- **症狀**：`codex_global_install_test`（`scripts/... Permission denied`）與
  `codex_mode_switch_test`（`verify-codex-mode` 的 `[[ -x ]]` 檢查 `hook file is not executable`）。
- **判準**：只對「被 `[[ -x ]]` 檢查的 Codex PreToolUse 進入點」「被直接執行的 script」
  「跨平台進入點一致」補 `100755`；**import-only 模組**（`hook_protocol`／`pii_patterns`／
  `security_checks`）與**以 `python3` 呼叫的 Claude hooks** 維持 `100644`。
- **範圍**：11 檔（scripts×2、codex `security_guard.py`／`pii_guard.py`／SDG `block_secrets.py`、
  copilot `decomposition_gate.py`、`shared/codex` 來源×2）。維持 `shared/codex` 來源與 plugin
  副本 mode 一致（`cp -p` sync）。純 mode 變更、無內容變更。

## 待確認：main 分支的角色

`main` 目前已同步為 `release`（`10ee985`，內容一致）。但**一旦 `main` 開始開發就會領先
`release`**。由於預設分支已改為 `release`，日常開發流程建議為：feature 分支 → PR → `release`。
`main` 是否保留（作為另一整合線）或淘汰，尚未定案——【假設】暫時保留，若確認不需要再刪除。

## 維運附註（gate 誤傷）

user-level plan_gate 的「核准旗標保護」會攔截**任何指令字串含 `.plan_approved`**，
包含唯讀命令與清理誤產生的 `.claude/.plan_approved!` 垃圾檔——需在系統終端機
（非 Claude session）處理。屬既有保護的預期副作用，非缺陷。

## 關聯
- [[2026-07-23-copilot-vscode-support-plan]]（Copilot decomposition-gate Phase 1）
- [[2026-07-23-wsl-core-filemode-exec-bit]]（exec-bit 漂移的根因 gotcha）
