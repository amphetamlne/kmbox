$sp = "D:\Project\c++\kmbox\tools\tmp\.venv\Lib\site-packages"
Write-Output "=== pip list ==="
& "D:\Project\c++\kmbox\tools\tmp\.venv\Scripts\pip.exe" list
Write-Output "=== all dll/pyd in site-packages ==="
Get-ChildItem $sp -Recurse -File -Include *.dll,*.pyd | ForEach-Object { Write-Output $_.FullName }
