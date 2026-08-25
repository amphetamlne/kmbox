$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output "=== CLion 目录结构 ==="
$clion = 'D:\Program Files\JetBrains\CLion 2026.2.1'
if (Test-Path $clion) {
    Get-ChildItem $clion -Name | ForEach-Object { Write-Output $_ }
    Write-Output "--- bin 下 mingw/llvm 相关 ---"
    Get-ChildItem "$clion\bin" -Name -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_ }
}
Write-Output ""
Write-Output "=== D:/ 一级目录 ==="
Get-ChildItem 'D:\' -Name -Directory | ForEach-Object { Write-Output $_ }
Write-Output ""
Write-Output "=== JetBrains Toolbox / .jdks / 工具链缓存 ==="
foreach ($p in @("$env:LOCALAPPDATA\JetBrains\Toolbox", "$env:USERPROFILE\.CLionCE2026.2", "$env:APPDATA\JetBrains")) {
    if (Test-Path $p) { Write-Output "[EXISTS] $p" } else { Write-Output "[MISS] $p" }
}
