# 在参考固件中查找 RawHID 控制接口的报告描述符定义
import io
import re

path = r"D:\Project\aimbot\firmware\source\SmartUniversalMouse\SmartUniversalMouse.ino"
lines = io.open(path, encoding="utf-8", errors="replace").read().splitlines()
pat = re.compile(r"RawHid|raw_hid|0xC0,\s*0xFF|0xFF,\s*0xC0|class\s+\w+|getShortName|USAGE", re.I)
for i, l in enumerate(lines):
    if pat.search(l):
        print(i + 1, l.rstrip())
