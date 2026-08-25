# -*- coding: utf-8 -*-
"""读取固件诊断通道：通过 MI_00 键盘接口 GET_REPORT(id=1) 回传 RawHID 状态。
用法：设备处于独立模式（Host 口未接鼠标）时运行。
"""
import sys
import time

try:
    import hid
except ImportError:
    print("NO_HIDAPI")
    sys.exit(2)

VID, PID = 0x9981, 0x4002

cands = [d for d in hid.enumerate() if d["vendor_id"] == VID and d["product_id"] == PID]
if not cands:
    print("NO_DEVICE (vid 9981 pid 4002 not found)")
    sys.exit(1)

for d in cands:
    print("candidate: page=%#06x usage=%#06x iface=%d path=%s" % (
        d.get("usage_page", 0), d.get("usage", 0),
        d.get("interface_number", -1), d.get("path", b"")))

for d in cands:
    dev = hid.device()
    try:
        dev.open_path(d["path"])
    except Exception as e:
        print("open_path failed: %s" % e)
        continue
    tag = "page=%#06x usage=%#06x" % (d.get("usage_page", 0), d.get("usage", 0))
    try:
        # 尝试多种请求形态，区分 Windows 拦截 / 固件 stall / 长度问题
        for getter, name, rid, ln in [
            (dev.get_input_report, "input", 1, 8),
            (dev.get_input_report, "input", 1, 9),
            (dev.get_input_report, "input", 0, 8),
            (dev.get_feature_report, "feature", 1, 8),
            (dev.get_feature_report, "feature", 0, 8),
        ]:
            try:
                r = getter(rid, ln)
                print("%s %s id=%d len=%d -> (%s) %s" % (
                    tag, name, rid, ln,
                    "OK %d bytes" % len(r) if r else "empty",
                    bytes(r).hex() if r else ""))
                if r and len(r) >= 8 and r[0] == 0xD1 and r[7] == 0xA5:
                    flags = r[4]
                    print("--- DIAG ---")
                    print("ctrl_report_cb_calls (host 请求过控制接口报告描述符次数): %d" % r[1])
                    print("rawhid_instance: %d" % r[2])
                    print("mirrored_itf_count: %d" % r[3])
                    print("flags: runtime_cfg_valid=%d xbox=%d ctrl_set_report_seen=%d (raw=%#04x)" % (
                        flags & 1, (flags >> 1) & 1, (flags >> 2) & 1, flags))
                    print("ctrl_get_report_calls: %d" % r[5])
                    print("itf0_report_cb_calls: %d" % r[6])
                    dev.close()
                    sys.exit(0)
            except Exception as e:
                print("%s %s id=%d len=%d -> ERROR: %s" % (tag, name, rid, ln, e))
    finally:
        dev.close()

print("NO_DIAG_DATA")
sys.exit(3)
