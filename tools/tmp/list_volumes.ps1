$out = "D:\Project\c++\kmbox\tools\tmp\volumes.txt"
Get-CimInstance Win32_LogicalDisk | ForEach-Object {
    "$($_.DeviceID) | $($_.VolumeName) | type=$($_.DriveType) | size=$($_.Size)"
} | Set-Content $out -Encoding UTF8
