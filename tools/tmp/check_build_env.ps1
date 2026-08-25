$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$home2 = $env:USERPROFILE
Write-Output "PICO_SDK_PATH=$env:PICO_SDK_PATH"
Write-Output "--- $home2\.pico-sdk ---"
if (Test-Path "$home2\.pico-sdk") { Get-ChildItem "$home2\.pico-sdk" | ForEach-Object { Write-Output $_.Name } } else { Write-Output "(不存在)" }
Write-Output "--- sdk 版本 ---"
if (Test-Path "$home2\.pico-sdk\sdk") { Get-ChildItem "$home2\.pico-sdk\sdk" | ForEach-Object { Write-Output $_.Name } } else { Write-Output "(无 sdk 目录)" }
foreach ($cmd in @('cmake','ninja','make','arm-none-eabi-gcc','picotool','bash','git')) {
    $c = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($c) { Write-Output "[OK]   $cmd -> $($c.Source)" } else { Write-Output "[MISS] $cmd" }
}
Write-Output "--- 关键文件直查 ---"
foreach ($p in @("$home2\.pico-sdk\cmake\v3.31.5\bin\cmake.exe",
                 "$home2\.pico-sdk\ninja\v1.12.1\ninja.exe",
                 "$home2\.pico-sdk\toolchain\14_2_Rel1\bin\arm-none-eabi-gcc.exe",
                 "$home2\.pico-sdk\picotool\2.1.1\picotool\picotool.exe")) {
    if (Test-Path $p) { Write-Output "[OK]   $p" } else { Write-Output "[MISS] $p" }
}
