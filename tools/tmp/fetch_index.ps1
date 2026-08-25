$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
$r = Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2273053' -UseBasicParsing -UserAgent $ua
$r.Content | Out-File -Encoding UTF8 D:\Project\c++\kmbox\tools\tmp\pico_index.json
Write-Output ("下载成功, 长度: " + $r.Content.Length)
Write-Output ("前80字符: " + $r.Content.Substring(0, [Math]::Min(80, $r.Content.Length)))
