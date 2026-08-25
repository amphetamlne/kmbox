# -*- coding: utf-8 -*-
"""快速验证 PIOKMbox RawHID 控制接口：
1. 枚举 HID 设备，找 usage_page=0xFFC0 / usage=0x0C00 的控制接口
2. 找到后发送 SmartUniversalMouse PING，等待 HEARTBEAT 应答并解析
"""
import sys
import time

try:
    import hid
except ImportError:
    print("NO_HIDAPI")
    sys.exit(2)

CONTROL_USAGE_PAGE = 0xFFC0
CONTROL_USAGE = 0x0C00

CMD_HANDSHAKE = 0x01
CMD_HEARTBEAT = 0x07
CMD_PING = 0xAB


def obfuscate(packet):
    for i in range(1, 7):
        packet[i] ^= 0x3C
    return packet


def deobfuscate(packet):
    return obfuscate(packet)


def make_ping():
    packet = bytearray(8)
    packet[0] = 0x5A
    packet[1] = CMD_PING
    packet[7] = 0
    for i in range(7):
        packet[7] ^= packet[i]
    return bytes(obfuscate(bytearray(packet)))


def main():
    print("=== HID enumerate ===")
    control_devs = []
    for d in hid.enumerate():
        up, u = d.get("usage_page") or 0, d.get("usage") or 0
        tag = " <-- CONTROL" if (up == CONTROL_USAGE_PAGE and u == CONTROL_USAGE) else ""
        if tag:
            control_devs.append(d)
        print("VID=%04X PID=%04X page=%04X usage=%04X %s | %s" % (
            d.get("vendor_id", 0), d.get("product_id", 0), up, u,
            tag, (d.get("product_string") or "")[:40]))

    if not control_devs:
        print("\nNO_CONTROL_INTERFACE_FOUND")
        return 1

    d = control_devs[0]
    print("\n=== open control interface ===")
    dev = hid.device()
    dev.open(d["vendor_id"], d["product_id"], d.get("serial_number"))
    dev.set_nonblocking(True)

    ping = make_ping()
    print("send PING (%d bytes): %s" % (len(ping), ping.hex()))
    # Windows hidapi: write 需要带 report id 前缀（本描述符无 report id，前缀 0x00）
    dev.write(b"\x00" + ping)

    deadline = time.time() + 2.0
    while time.time() < deadline:
        resp = dev.read(64, timeout_ms=200)
        if not resp:
            continue
        data = deobfuscate(bytearray(resp[:8]))
        print("recv (%d bytes): %s" % (len(resp), bytes(resp[:8]).hex()))
        if data[0] == 0x5A and data[1] == CMD_HEARTBEAT:
            status, version = data[2], data[3]
            gen = data[4] | (data[5] << 8)
            print("HEARTBEAT OK: status=%02X version=%02X desc_gen=%d" % (status, version, gen))
            if status & 0x02:
                print("  bit1: host mouse attached")
            dev.close()
            return 0
    print("NO_HEARTBEAT_RESPONSE")
    dev.close()
    return 3


if __name__ == "__main__":
    sys.exit(main())
