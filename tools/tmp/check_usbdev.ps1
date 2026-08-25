# 用 WinRT Devices 枚举 USB 设备，打印 revision(bcdDevice) / 接口数，判断 KMBox 是否在位
[Windows.Devices.Enumeration.DeviceInformation, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Usb.UsbDevice, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$selector = [Windows.Devices.Usb.UsbDevice]::GetDeviceSelector(0x046D, 0xC084)
$devices = [Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($selector).GetAwaiter().GetResult()
Write-Output ("matched devices: " + $devices.Count)

foreach ($di in $devices) {
    Write-Output ("---- id: " + $di.Id)
    $usb = [Windows.Devices.Usb.UsbDevice]::FromIdAsync($di.Id).GetAwaiter().GetResult()
    if ($null -eq $usb) { Write-Output "  (cannot open)"; continue }
    $d = $usb.DeviceDescriptor
    Write-Output ("  vid={0:X4} pid={1:X4} bcdDevice={2:X4} bcdUSB={3:X4} class={4:X2} numConfigs={5}" -f `
        $d.VendorId, $d.ProductId, $d.BcdDevice, $d.BcdUsb, $d.DeviceClass, $d.NumberOfConfigurations)
    $cfg = $usb.Configuration
    Write-Output ("  config interfaces: " + $cfg.UsbInterfaces.Count)
    foreach ($itf in $cfg.UsbInterfaces) {
        Write-Output ("    itf#{0} class={1:X2} subclass={2:X2} protocol={3:X2} descriptors={4}" -f `
            $itf.InterfaceNumber, $itf.ClassCode, $itf.SubclassCode, $itf.ProtocolCode, $itf.Descriptors.Count)
    }
}
