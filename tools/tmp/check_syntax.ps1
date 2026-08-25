$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$files = @(
    'D:\Project\c++\kmbox\tools\build_kmbox_windows.ps1',
    'D:\Project\c++\kmbox\tools\flash_kmbox_windows.ps1'
)
foreach ($f in $files) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Write-Output "FAIL: $f"
        $errors | ForEach-Object { Write-Output $_.Message }
    } else {
        Write-Output "OK: $f"
    }
}
