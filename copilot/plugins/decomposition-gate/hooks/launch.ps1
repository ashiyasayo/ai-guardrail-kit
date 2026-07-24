# Copilot decomposition-gate 啟動器（Windows）。
# 由 .github/hooks 設定以 powershell -Command "& '.\.github\hooks\launch.ps1'" 呼叫。
#
# 職責：把 VS Code 送來的原始 stdin 位元組原樣交給 python hook，並回傳其 stdout。
# 為何需要 launcher：VS Code 無法直接生 python.exe（Store 別名/參數 tokenize 問題），
#   須經 powershell 中介；且必須以「原始位元組」搬 stdin，避免中文被 PowerShell
#   字串管線轉成 ?（Phase 0 spike 實證）。
# 資安鐵律：任何錯誤都必須自印 deny JSON——VS Code 對 hook 執行錯誤預設 fail-open
#   （NonBlockingError → 工具照放行），故絕不能讓例外逸出而無輸出。
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
try {
    $py = $env:GUARDRAIL_PYTHON
    if (-not $py) {
        # 排除 WindowsApps 的 Store 別名（VS Code 生子程序時呼叫不到）
        $found = Get-Command python.exe -ErrorAction SilentlyContinue |
                 Where-Object { $_.Source -notlike "*WindowsApps*" } |
                 Select-Object -First 1
        if ($found) { $py = $found.Source }
    }
    if (-not $py) { throw "python.exe not found; set GUARDRAIL_PYTHON to the interpreter path" }
    $script = Join-Path $PSScriptRoot "decomposition_gate.py"

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
    $deny = @{ hookSpecificOutput = @{ hookEventName = "PreToolUse"; permissionDecision = "deny";
              permissionDecisionReason = "decomposition-gate launcher error: $($_.Exception.Message)" } }
    [Console]::Out.Write(($deny | ConvertTo-Json -Compress -Depth 5))
}
