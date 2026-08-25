$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output "=== tools/CMakeLists.txt 中 uf2 相关 ==="
Select-String -Path 'C:\Users\woan\.pico-sdk\sdk\2.2.0-fresh\tools\CMakeLists.txt' -Pattern 'uf2' |
    Select-Object -First 20 |
    ForEach-Object { Write-Output ("{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }
Write-Output ""
Write-Output "=== on_device.cmake 中 uf2 相关 ==="
Select-String -Path 'C:\Users\woan\.pico-sdk\sdk\2.2.0-fresh\src\cmake\on_device.cmake' -Pattern 'uf2' |
    Select-Object -First 10 |
    ForEach-Object { Write-Output ("{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }
