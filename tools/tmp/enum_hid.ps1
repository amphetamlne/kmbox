# 枚举所有 HID 设备，重点查找 usage_page=0xFFC0 的 RawHID 控制接口
$py = "D:\Project\c++\kmbox\tools\tmp\.venv\Scripts\python.exe"
$code = @'
import hid
devs = hid.enumerate()
print(f"total HID devices: {len(devs)}")
keep = [0x9981, 0x3554, 0x046D]
for d in devs:
    if d["vendor_id"] not in keep and d.get("usage_page", 0) != 0xFFC0:
        continue
    page = d.get("usage_page", 0)
    usage = d.get("usage", 0)
    mark = "  <<< CONTROL" if page == 0xFFC0 else ""
    print("vid={:#06x} pid={:#06x} page={:#06x} usage={:#06x} iface={} path={}{}".format(
        d["vendor_id"], d["product_id"], page, usage,
        d.get("interface_number", -1), d.get("path", b"")[:80], mark))
'@
& $py -c $code
