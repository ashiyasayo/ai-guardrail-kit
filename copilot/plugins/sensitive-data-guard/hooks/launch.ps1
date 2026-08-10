# Copilot sensitive-data-guard 啟動器（Windows）。
#
# 由 .github/hooks 設定以下列形式呼叫（第一參數＝目標腳本，第二參數＝事件名稱）：
#   powershell -NoProfile -ExecutionPolicy Bypass -Command
#     "& '.\.github\hooks\launch.ps1' sensitive_data_guard.py PreToolUse"
#
# 為何參數化（decomposition-gate 的啟動器是硬寫腳本名）：本模式有兩個進入點
#   （PreToolUse 與 UserPromptSubmit），且錯誤路徑的 hookEventName 依事件而異。
#   刻意不與 decomposition-gate 共用啟動器：vault 記載 Windows 啟動器是整個 Copilot
#   移植最難搞定、風險最高的產物，而兩模式互斥安裝、永不共存，跨模式分歧沒有
#   執行期交互風險。
#
# 職責：把 VS Code 送來的原始 stdin 位元組原樣交給 python hook，並回傳其 stdout。
# 為何需要 launcher：VS Code 無法直接生 python.exe（Store 別名/參數 tokenize 問題），
#   須經 powershell 中介；且必須以「原始位元組」搬 stdin，避免中文被 PowerShell
#   字串管線轉成 ?（Phase 0 spike 實證）。
# 資安鐵律：任何錯誤都必須自印 deny JSON——VS Code 對 hook 執行錯誤預設 fail-open
#   （NonBlockingError → 工具照放行），故絕不能讓例外逸出而無輸出。
param(
    [string]$HookScript = "",
    [string]$HookEvent = "PreToolUse"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# 錯誤輸出用的事件名稱先行淨化：形狀必須與事件相符，對 UserPromptSubmit 輸出
# PreToolUse 形狀很可能被 VS Code 忽略而 fail-open（等同沒擋）。
$safeEvent = if ($HookEvent -eq "UserPromptSubmit") { "UserPromptSubmit" } else { "PreToolUse" }

try {
    # 腳本名限制為單純檔名：設定檔若被篡改，不得藉此執行 hooks 目錄外的檔案
    if (-not $HookScript) { throw "missing hook script argument" }
    if ($HookScript -match '[\\/]' -or $HookScript -notmatch '^[A-Za-z0-9_.-]+\.py$') {
        throw "invalid hook script argument: $HookScript"
    }
    $script = Join-Path $PSScriptRoot $HookScript
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        throw "hook script not found: $HookScript"
    }

    $py = $env:GUARDRAIL_PYTHON
    if (-not $py) {
        # 排除 WindowsApps 的 Store 別名（VS Code 生子程序時呼叫不到）
        $found = Get-Command python.exe -ErrorAction SilentlyContinue |
                 Where-Object { $_.Source -notlike "*WindowsApps*" } |
                 Select-Object -First 1
        if ($found) { $py = $found.Source }
    }
    if (-not $py) { throw "python.exe not found; set GUARDRAIL_PYTHON to the interpreter path" }

    # 讀原始位元組，不經 PowerShell 字串編碼（否則中文會被轉成 ?）
    $memory = New-Object System.IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($memory)
    $bytes = $memory.ToArray()

    # 以 .NET Process 直接把原始位元組寫進 python 的 stdin、以 UTF-8 讀回 stdout
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $py
    $psi.Arguments = "`"$script`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = [System.Diagnostics.Process]::Start($psi)
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "python exit $($process.ExitCode)" }
    [Console]::Out.Write($stdout)
} catch {
    $deny = @{ hookSpecificOutput = @{ hookEventName = $safeEvent; permissionDecision = "deny";
              permissionDecisionReason = "sensitive-data-guard launcher error: $($_.Exception.Message)" } }
    [Console]::Out.Write(($deny | ConvertTo-Json -Compress -Depth 5))
}
