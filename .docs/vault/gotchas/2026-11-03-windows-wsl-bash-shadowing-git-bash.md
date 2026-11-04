# Windows WSL Bash 可能遮蔽 Git for Windows Bash

日期：2026-11-03

在 Windows 原生 Python 以 `shutil.which("bash")` 尋找 Bash 時，`PATH` 內容或啟動方式可能
讓結果落到 `C:\Windows\System32\bash.exe`。該檔是 WSL launcher，不是 Git Bash；用它
執行 extensionless Bash 測試腳本會回報存取拒絕，Codex runtime manager 再包裝成
`E_HOOK_FAILED`。

修正原則：正式 `.exe`／`.cmd`／`.bat` 仍直接執行；只有 Windows、目標是 extensionless
腳本且首選 Bash 正好是 `System32\bash.exe` 時，才由 `git.exe` 的安裝根目錄依序尋找
`bin\bash.exe` 與 `usr\bin\bash.exe`。不要只硬編碼單一 Git 安裝路徑，也不要全面取代
使用者 PATH 中正常的 Bash。

回歸 seam 位於 `tests/codex_runtime_manager_test.sh`：注入 WSL Bash、Git CMD 路徑及虛擬
檔案存在檢查，直接驗證 resolver 的選擇；整合驗證另涵蓋 global install、mode switch 與
marketplace refresh。
