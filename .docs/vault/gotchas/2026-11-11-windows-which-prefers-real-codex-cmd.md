# Windows 上 shutil.which 會回傳真的 codex.CMD，不是測試的假 Codex

日期：2026-11-11

## 現象

`codex_global_install_test.sh`、`codex_refresh_guardrail_ref_test.sh`（以及 full profile 的
`codex_mode_switch_test.sh`）在 Windows／Git Bash 以 `E_HOOK_FAILED: Codex plugin operation
failed` 失敗；Linux CI 通過。

## 根因

測試把沒有副檔名的假 Codex 放在 PATH 最前面，但 Windows 上 Python 的
`shutil.which("codex")` 依 `PATHEXT` 比對，實測（Python 3.15.2）回傳 npm 全域目錄的
`codex.CMD`，而不是排在前面的假檔。`codex-runtime-manager.py` 的 `_run_codex_plugin`
以 `suffix.lower()` 把 `.CMD` 視為正式 Codex 直接執行，所以測試實際呼叫了真的 Codex CLI，
非零結束後被包成 `E_HOOK_FAILED`。錯誤訊息不含 stderr，光看訊息無法分辨。

## 排除的假設

- WSL launcher 或 `WindowsApps` 的 bash 遮蔽 Git Bash：診斷顯示 `bash` 解析到
  `C:\Program Files\Git\usr\bin\bash.EXE`，不是原因（與
  `2026-11-03-windows-wsl-bash-shadowing-git-bash.md` 是不同問題）。

## 修正

修在測試端，不改 manager 的正式行為：`tests/helpers/install-fake-codex` 在 Windows 另外放
同目錄的 `codex.cmd`，內容只是以目前 Bash 的 Windows 路徑轉呼叫假檔。副檔名比對會先命中
暫存目錄，manager 既有的 `.cmd` 分支直接執行它。新增使用假 Codex 的測試時，一律呼叫這個
helper，不要自己 `cp` 假檔。

不採用的做法：讓 manager 改成「PATH 順序優先、不分副檔名」——npm 目錄同時有 sh 版
`codex` 與 `codex.cmd`，會改變正式行為；新增環境變數覆寫執行檔會擴大攻擊面。

## 診斷方法

用測試相同的 PATH 順序，直接看解析結果：

    d=$(mktemp -d); cp tests/helpers/fake-codex "$d/codex"
    PATH="$d:$PATH" python -c "import shutil; print(shutil.which('codex'))"

結果若不在 `$d` 底下，就是這個問題。

## 未確認

2026-11-04（v0.12.0）同一台機器這些測試通過的原因沒有查明；`shutil.which` 在 Windows 的
比對順序文件沒有說明。
