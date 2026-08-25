$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$candidates = @(
    'C:\Users\woan\.local\bin\python3.11.exe',
    'C:\Users\woan\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe',
    'C:\Users\woan\Miniconda3\python.exe'
)
foreach ($p in $candidates) {
    if (Test-Path $p) {
        try {
            $ver = & $p --version 2>&1
            Write-Output "[WORKS] $p -> $ver"
        } catch {
            Write-Output "[BROKEN] $p"
        }
    } else {
        Write-Output "[MISS] $p"
    }
}
Write-Output "--- 注册表 PythonCore（CMake FindPython 会读取） ---"
foreach ($hive in @('HKCU:\Software\Python\PythonCore','HKLM:\Software\Python\PythonCore')) {
    if (Test-Path $hive) {
        Get-ChildItem $hive | ForEach-Object {
            $ip = Get-ItemProperty "$($_.PSPath)\InstallPath" -ErrorAction SilentlyContinue
            Write-Output "$($_.PSChildName): $($ip.ExecutablePath)"
        }
    }
}
