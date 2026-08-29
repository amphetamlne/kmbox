#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# /// script
# requires-python = ">=3.8"
# dependencies = []
# ///
"""flash_batch.py — KMBox 固件批量烧录工具（Windows / RP2350 BOOTSEL）

纯标准库实现，替代 tools/flash_kmbox_windows.ps1，并增加多设备批量支持。

用法:
    python flash_batch.py                     # 交互模式: 自动找固件, 等待/选择设备并烧录
    python flash_batch.py --uf2 固件.uf2      # 指定固件文件
    python flash_batch.py --all               # 批量模式: 依次烧录当前所有 BOOTSEL 设备
    python flash_batch.py --wait 90           # 等待设备超时改为 90 秒
    python flash_batch.py --list              # 仅列出当前检测到的 BOOTSEL 设备

烧录步骤:
    1. 按住板上的 BOOTSEL 按钮, 插入 USB 线（或按住 BOOTSEL 再按一下 RESET）
    2. 脚本检测到 BOOTSEL U 盘（卷标 RPI-RP2 / KMBOX-BRDG）后自动复制固件
    3. 复制完成设备自动重启, 盘符消失即烧录成功

直接运行: uv run flash_batch.py
打包 EXE: uvx pyinstaller --onefile --console --name flash_batch tools/flash_batch.py
"""

import argparse
import ctypes
import os
import sys
import time
from pathlib import Path

__version__ = "1.0.0"

# ---------------------------------------------------------------------------
# Windows 卷管理 API（纯 ctypes, 无第三方依赖）
# ---------------------------------------------------------------------------

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

DRIVE_UNKNOWN = 0
DRIVE_NO_ROOT_DIR = 1
DRIVE_REMOVABLE = 3

# 已知的 BOOTSEL 卷标（KMBOX-BRDG 为白标烧录后的 Bridge 设备）
BOOTSEL_LABELS = {"RPI-RP2", "KMBOX-BRDG"}


class BootDrive:
    """一个处于 BOOTSEL 模式的板子（挂载为 U 盘）"""

    def __init__(self, letter: str, root: str, label: str):
        self.letter = letter          # 如 "E"
        self.root = root              # 如 "E:\\"
        self.label = label            # 卷标, 如 "RPI-RP2"

    def __str__(self) -> str:
        return f"{self.letter}:  (卷标={self.label or '无'})"


def _volume_label(root: str) -> str:
    """读取卷标, 失败（设备未就绪）返回空串"""
    name = ctypes.create_unicode_buffer(261)
    ok = kernel32.GetVolumeInformationW(
        ctypes.c_wchar_p(root), name, ctypes.sizeof(name), None, None, None, None, 0
    )
    return name.value if ok else ""


def _drive_bitmask() -> int:
    return kernel32.GetLogicalDrives() & 0x3FFFFFF


def detect_bootsel_drives() -> list:
    """枚举所有盘符, 返回处于 BOOTSEL 模式的设备列表"""
    found = []
    bitmask = _drive_bitmask()
    for i in range(26):
        if not (bitmask >> i) & 1:
            continue
        letter = chr(ord("A") + i)
        root = f"{letter}:\\"
        dtype = kernel32.GetDriveTypeW(ctypes.c_wchar_p(root))
        label = _volume_label(root)
        if label.upper() in BOOTSEL_LABELS:
            found.append(BootDrive(letter, root, label))
        elif dtype == DRIVE_REMOVABLE:
            # 卷标不匹配时, 通过 INFO_UF2.TXT 标识文件二次确认
            try:
                if (Path(root) / "INFO_UF2.TXT").is_file():
                    found.append(BootDrive(letter, root, label))
            except OSError:
                pass
    return found


def drive_letter_present(letter: str) -> bool:
    """判断盘符是否仍然挂载（烧录后设备重启, 盘符会消失）"""
    return bool((_drive_bitmask() >> (ord(letter) - ord("A"))) & 1)


# ---------------------------------------------------------------------------
# 固件查找
# ---------------------------------------------------------------------------

def _script_base() -> Path:
    """兼容 PyInstaller 打包与源码运行两种场景"""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def find_firmware(explicit: str = None) -> Path:
    """定位 .uf2 固件: 优先 --uf2 参数, 否则按 ps1 脚本相同的优先级查找构建产物"""
    if explicit:
        p = Path(explicit)
        if not p.is_file():
            raise FileNotFoundError(f"指定的固件不存在: {p}")
        return p.resolve()

    base = _script_base()
    # 候选根目录: 脚本所在仓库根目录, 其次当前工作目录
    roots = [base.parent, Path.cwd()]
    candidates = [
        Path("build-waveshare") / "PIOKMbox.uf2",
        Path("build-metro") / "PIOKMbox.uf2",
    ]
    for r in roots:
        for rel in candidates:
            p = r / rel
            if p.is_file():
                return p.resolve()

    # 兜底提示: 列出各构建目录里实际存在的 uf2, 帮助用户定位
    hints = []
    for r in roots:
        if (r / "CMakeLists.txt").is_file() or (r / "tools").is_dir():
            hints += [str(p) for p in sorted(r.glob("build*/**/*.uf2")) if p.is_file()]
    msg = "未找到 PIOKMbox.uf2, 请先运行 tools/build_kmbox_windows.ps1 编译,\n" \
          "或用 --uf2 参数指定固件路径。"
    if hints:
        msg += "\n当前可用的 .uf2 文件:\n  " + "\n  ".join(hints)
    raise FileNotFoundError(msg)


# ---------------------------------------------------------------------------
# 烧录核心
# ---------------------------------------------------------------------------

CHUNK = 64 * 1024


def _copy_with_progress(src: Path, dest: Path) -> bool:
    """分块复制并显示进度; 返回 False 表示中途遇到 USB 断开"""
    total = src.stat().st_size
    written = 0
    last_pct = -10
    try:
        with open(src, "rb") as fsrc, open(dest, "wb") as fdst:
            while True:
                chunk = fsrc.read(CHUNK)
                if not chunk:
                    break
                fdst.write(chunk)
                written += len(chunk)
                pct = int(written * 100 / total)
                if pct >= last_pct + 10:
                    last_pct = pct
                    print(f"\r    正在复制... {pct:3d}% ({written}/{total} 字节)", end="", flush=True)
            print("\r    正在复制... 100%", flush=True)
            try:
                fdst.flush()
                os.fsync(fdst.fileno())  # BOOTSEL 盘可能不支持, 失败可忽略
            except OSError:
                pass
        return True
    except OSError as e:
        print(f"\r    复制中断: {e}", flush=True)
        print("    （复制过程中设备断开, 通常是烧录完成瞬间的正常现象）")
        return False


def _open_for_write_retry(dest: Path, attempts: int = 6, delay: float = 0.5):
    """卷刚挂载时可能短暂未就绪, 对打开写入做有限重试"""
    last_err = None
    for _ in range(attempts):
        try:
            return open(dest, "wb")
        except OSError as e:
            last_err = e
            time.sleep(delay)
    raise last_err


def flash_one(drive: BootDrive, uf2: Path, verify_timeout: float = 15.0) -> str:
    """向单块板子烧录, 返回状态: ok / warn / fail"""
    dest = Path(drive.root) / uf2.name
    print(f"  目标设备: {drive}")
    print(f"  固件文件: {uf2.name} ({uf2.stat().st_size} 字节)")
    try:
        # 先确保写入通道可用（重试覆盖卷未就绪的情况）
        f = _open_for_write_retry(dest)
        f.close()
    except OSError as e:
        print(f"  结果: 失败 — 无法写入 {dest}: {e}")
        return "fail"

    complete = _copy_with_progress(uf2, dest)

    # 等待设备重启（盘符消失）
    print(f"    等待设备重启（盘符 {drive.letter}: 消失, 最长 {verify_timeout:.0f} 秒）...")
    deadline = time.time() + verify_timeout
    while time.time() < deadline:
        if not drive_letter_present(drive.letter):
            break
        time.sleep(0.5)

    if not drive_letter_present(drive.letter):
        if complete:
            print("  结果: 烧录完成, 板子已重启")
        else:
            print("  结果: 烧录完成（复制中断但设备已重启, 与 PS1 脚本行为一致, 视为成功）")
        return "ok"

    print("  结果: 警告 — 盘符仍存在, 烧录可能未完成, 请重新上电后验证")
    return "warn"


# ---------------------------------------------------------------------------
# 交互与批量流程
# ---------------------------------------------------------------------------

def wait_for_devices(timeout: float, poll: float = 0.5) -> list:
    """轮询等待 BOOTSEL 设备出现, 超时返回当前检测结果（可能为空）"""
    print(f">>> 等待 BOOTSEL 设备（最长 {timeout:.0f} 秒）...")
    print("    请按住板上的 BOOTSEL 按钮, 插入 USB 线（或按住 BOOTSEL 再按一下 RESET）")
    deadline = time.time() + timeout
    while time.time() < deadline:
        drives = detect_bootsel_drives()
        if drives:
            print("\r" + " " * 60 + "\r", end="", flush=True)  # 清除等待行
            print(f"    检测到 {len(drives)} 个设备")
            return drives
        remain = deadline - time.time()
        print(f"\r    已等待 {timeout - remain:5.1f}s / {timeout:.0f}s, 未检测到设备...",
              end="", flush=True)
        time.sleep(poll)
    print()
    return []


def choose_devices(drives: list, flash_all: bool) -> list:
    """多设备时列出菜单供选择; --all 直接全部烧录"""
    if flash_all or len(drives) == 1:
        return drives
    print(f">>> 检测到 {len(drives)} 个 BOOTSEL 设备:")
    for i, d in enumerate(drives, 1):
        print(f"    [{i}] {d}")
    print("    [a] 全部烧录    [q] 退出")
    while True:
        try:
            choice = input("选择要烧录的设备: ").strip().lower()
        except EOFError:
            return []
        if choice == "q":
            return []
        if choice == "a":
            return drives
        if choice.isdigit() and 1 <= int(choice) <= len(drives):
            return [drives[int(choice) - 1]]
        print(f"    无效输入, 请输入 1-{len(drives)}, a 或 q")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="KMBox 固件批量烧录工具（RP2350 BOOTSEL, 仅标准库）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例:\n"
               "  flash_batch.py                    交互模式, 自动找固件\n"
               "  flash_batch.py --all              批量烧录所有 BOOTSEL 设备\n"
               "  flash_batch.py --uf2 D:\\fw.uf2    指定固件\n",
    )
    parser.add_argument("--uf2", help="固件 .uf2 路径（默认自动查找 build-waveshare/build-metro 产物）")
    parser.add_argument("--all", action="store_true", help="批量模式: 依次烧录所有检测到的设备, 不弹菜单")
    parser.add_argument("--wait", type=float, default=60.0, help="等待 BOOTSEL 设备的超时秒数（默认 60）")
    parser.add_argument("--verify", type=float, default=15.0, help="等待设备重启的验证超时秒数（默认 15）")
    parser.add_argument("--list", action="store_true", help="仅列出当前检测到的 BOOTSEL 设备后退出")
    parser.add_argument("--version", action="version", version=f"flash_batch {__version__}")
    args = parser.parse_args()

    # Windows 控制台 UTF-8 输出（兼容中文路径/消息）
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except Exception:
                pass

    print(f"=== KMBox 批量烧录工具 v{__version__} ===")

    # 1. 定位固件
    try:
        uf2 = find_firmware(args.uf2)
    except FileNotFoundError as e:
        print(f">>> 错误: {e}")
        return 2
    print(f">>> 固件: {uf2}")

    # 2. 检测设备（先查一次, 没有再进入等待; --list 模式不等待）
    drives = detect_bootsel_drives()
    if not drives:
        if args.list:
            print(">>> 当前未检测到 BOOTSEL 设备")
            return 0
        drives = wait_for_devices(args.wait)
        if not drives:
            print(">>> 等待超时, 未检测到 BOOTSEL 设备, 退出")
            return 3
    else:
        print(f">>> 检测到 {len(drives)} 个 BOOTSEL 设备")

    if args.list:
        for d in drives:
            print(f"    {d}")
        return 0

    # 3. 选择设备
    targets = choose_devices(drives, args.all)
    if not targets:
        print(">>> 未选择任何设备, 退出")
        return 0

    # 4. 依次烧录
    print(f">>> 开始烧录, 共 {len(targets)} 个设备")
    results = {}
    for idx, drive in enumerate(targets, 1):
        print(f"\n[{idx}/{len(targets)}] 正在烧录...")
        try:
            results[drive.letter] = flash_one(drive, uf2, args.verify)
        except KeyboardInterrupt:
            print("\n>>> 用户中断")
            return 130
        except Exception as e:  # 防御性兜底: 单设备失败不影响后续设备
            print(f"  结果: 失败 — 未预期的异常: {e}")
            results[drive.letter] = "fail"
        # 给系统一点时间识别盘符变化, 避免误判下一个设备
        time.sleep(1.0)

    # 5. 汇总
    ok = sum(1 for s in results.values() if s == "ok")
    warn = sum(1 for s in results.values() if s == "warn")
    fail = sum(1 for s in results.values() if s == "fail")
    print("\n=== 烧录汇总 ===")
    for letter, status in results.items():
        mark = {"ok": "成功", "warn": "警告", "fail": "失败"}[status]
        print(f"  {letter}:  {mark}")
    print(f"=== 完成: {ok} 成功 / {warn} 警告 / {fail} 失败 ===")

    # 双击 EXE 运行时暂停, 避免窗口一闪而过
    if getattr(sys, "frozen", False) and len(sys.argv) <= 1:
        try:
            input("\n按回车键退出...")
        except EOFError:
            pass

    return 0 if fail == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n>>> 用户中断")
        sys.exit(130)
