$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
foreach ($p in @('python','python3','py')) {
    $c = Get-Command $p -ErrorAction SilentlyContinue
    if ($c) { Write-Output "[OK]   $p -> $($c.Source)" } else { Write-Output "[MISS] $p" }
}
Write-Output "--- 常见 Python 安装位置 ---"
foreach ($path in @('C:\Python311\python.exe','C:\Python312\python.exe','C:\Python313\python.exe',
                    "$env:LOCALAPPDATA\Programs\Python",
                    "$env:USERPROFILE\.local\bin",
                    "$env:USERPROFILE\scoop\apps\python")) {
    if (Test-Path $path) {
        Write-Output "[EXISTS] $path"
        if ((Get-Item $path).PSIsContainer) { Get-ChildItem $path -Filter 'python*.exe' -Recurse -Depth 1 -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object { Write-Output "         -> $($_.FullName)" } }
    } else {
        Write-Output "[MISS]   $path"
    }
}
Write-Output "--- PATH 中的 python ---"
$env:PATH -split ';' | Where-Object { $_ -match 'python|conda' } | ForEach-Object { Write-Output $_ }
