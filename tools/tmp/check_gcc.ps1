$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$gcc = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\mingw\bin\gcc.exe'
$gpp = 'D:\Program Files\JetBrains\CLion 2026.2.1\bin\mingw\bin\g++.exe'
Write-Output "=== gcc ==="
& $gcc --version
Write-Output "=== g++ ==="
& $gpp --version
