$out = "D:\Project\c++\kmbox\tools\tmp\g102_state.txt"
$lines = @()
$compId = 'USB\VID_046D&PID_C084\5&3207D635&0&7'
$all = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
foreach ($d in $all) {
    $parent = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue).Data
    if ($parent -eq $compId) {
        $lines += "CHILD: $($d.InstanceId)  class=$($d.Class)  status=$($d.Status)  name=$($d.FriendlyName)"
    }
}
if ($lines.Count -eq 0) { $lines += "NO_CHILDREN_FOUND" }
$lines | Set-Content $out -Encoding UTF8
