$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$mingw = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\mingw'
Write-Output "=== mingw 目录内容 ==="
Get-ChildItem $mingw -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_.Name }
Write-Output ""
Write-Output "=== 递归找所有 exe（前20个） ==="
Get-ChildItem $mingw -Recurse -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 20 | ForEach-Object { Write-Output $_.FullName }
Write-Output ""
Write-Output "=== clang 目录 ==="
Get-ChildItem 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\clang' -Recurse -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 10 | ForEach-Object { Write-Output $_.FullName }
