$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output "=== winget search picotool ==="
winget search picotool --accept-source-agreements 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "=== winget search pioasm ==="
winget search pioasm --accept-source-agreements 2>&1 | ForEach-Object { Write-Output $_ }
Write-Output "=== winget search mingw ==="
winget search mingw --accept-source-agreements 2>&1 | Select-Object -First 15 | ForEach-Object { Write-Output $_ }
