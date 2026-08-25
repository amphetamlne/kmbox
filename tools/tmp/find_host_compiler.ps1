$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output "=== cmake-build-debug 缓存中的编译器 ==="
$cache = 'D:\Project\c++\kmbox\cmake-build-debug\CMakeCache.txt'
if (Test-Path $cache) {
    Select-String -Path $cache -Pattern 'CMAKE_C_COMPILER:|CMAKE_CXX_COMPILER:|CMAKE_MAKE_PROGRAM|CMAKE_GENERATOR:' | ForEach-Object { Write-Output $_.Line }
} else { Write-Output "(无缓存)" }
Write-Output ""
Write-Output "=== 常见位置搜索 gcc.exe / cl.exe ==="
$searchRoots = @(
    "$env:LOCALAPPDATA\Programs",
    "$env:LOCALAPPDATA\JetBrains",
    "$env:APPDATA\JetBrains",
    'C:\msys64',
    'D:\msys64',
    'C:\mingw64',
    'C:\msys',
    'C:\Qt',
    'D:\Qt'
)
foreach ($root in $searchRoots) {
    if (Test-Path $root) {
        Get-ChildItem -Path $root -Recurse -Include 'gcc.exe','cl.exe','g++.exe' -ErrorAction SilentlyContinue -Depth 6 |
            Select-Object -First 4 |
            ForEach-Object { Write-Output $_.FullName }
    }
}
