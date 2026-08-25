# Waveshare RP2350-USB-A 使用指南

本指南面向使用 **微雪（Waveshare）RP2350-USB-A** 开发板运行 PIOKMbox 主固件的用户，
涵盖硬件说明、引脚映射、编译、烧录、验证与故障排查。

> 参考资料：[微雪官方 Wiki](https://www.waveshare.net/wiki/RP2350-USB-A)。
> 本项目不依赖微雪官方示例包，固件自带完整的 Pico SDK + PIO-USB Host 协议栈，
> 只需板级引脚配置正确即可（已内置于 `boards/waveshare_rp2350_usb_a.h`）。

---

## 1. 硬件概况

| 项目 | 说明 |
|:---|:---|
| 主控 | RP2350**A**（QFN-56，仅 GPIO0–29，无 GPIO30+） |
| Flash | 2 MB（Winbond W25Q16JVUXIQ） |
| 晶振 | 12 MHz |
| 顶部 Type-C 口 | USB Device / 供电 / UF2 烧录（连电脑） |
| 底部 USB-A 母座 | USB Host（插鼠标/键盘外设） |
| RGB | WS2812，GPIO16，3V3 供电 |
| 按键 | 仅 BOOTSEL / RESET，无用户按键 |
| 引出排针 | GPIO0–10、GPIO26–29、3V3、GND |

### 固件使用的引脚映射

已在根 `CMakeLists.txt` 的 `waveshare_rp2350_usb_a` 分支中配置：

| 功能 | GPIO | 备注 |
|:---|:---|:---|
| USB Host D+ | 12 | 底部 USB-A 口，经 27R 串阻 |
| USB Host D- | 13 | 底部 USB-A 口，经 27R 串阻 |
| WS2812 RGB | 16 | 状态指示灯 |
| UART0 TX/RX | 0 / 1 | KMBox 串口命令输入（115200） |
| USB 5V 使能 | 15（占位） | 该板 VBUS 直连 VSYS 常供电，无使能脚 |
| LED | 17（占位） | 该板无独立 LED |

---

## 2. ⚠️ 热插拔注意：R13 电阻

USB-A 口出厂贴有 **R13（1.5K D+ 上拉电阻）**，使该口默认也可作 Device。
按微雪官方 FAQ：**如需 Host 模式可靠热插拔，应拆除 R13**（拆除后该口不能再作 Device）。

- 不拆 R13：开机时已插着的鼠标/键盘可正常枚举（当前固件已验证可用），
  但**运行中插拔外设可能无法被识别**，需要重启板子。
- 拆 R13：支持运行中热插拔外设。

---

## 3. 编译（Windows）

### 环境要求

- CMake ≥ 3.13、Ninja
- arm-none-eabi GCC 工具链（Pico SDK 官方工具链即可）
- Python 3（SDK 构建脚本使用）
- Pico SDK 2.2.0（`PICO_SDK_PATH`）
- picotool（可用 `-Dpicotool_DIR=<已安装的picotool目录>` 复用，避免联网下载）

### 一键脚本

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build_kmbox_windows.ps1
```

产物：`build-waveshare/PIOKMbox.uf2`

> 脚本内的工具链/SDK 路径按默认安装位置编写，如安装位置不同请直接修改脚本顶部变量。

### 手动编译

```powershell
cmake -S . -B build-waveshare -G Ninja `
  -DPICO_BOARD=waveshare_rp2350_usb_a `
  -DPICO_PLATFORM=rp2350-arm-s `
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-waveshare -j
```

### TinyUSB 版本注意

必须使用 SDK 自带的 TinyUSB（0.18.0，由 SDK 子模块钉住）。
若 SDK 中的 `lib/tinyusb` 被换成了 master 分支，会出现
`usbd_edpt_xfer` 参数不匹配的编译错误（新 API 多了 `is_isr` 参数）。
修复：在 SDK 的 `lib/tinyusb` 目录执行
`git fetch --depth 1 origin 86ad6e56c1700e85f1c5678607a762cfe3aa2f47 && git checkout 86ad6e56`。

---

## 4. 烧录

1. 按住板上 **BOOTSEL** 键，同时按一下 **RESET**（或保持按住 BOOTSEL 插入 USB-C），
   板子会以 U 盘形式挂载（盘名通常为 `RP2350`）。
2. 把 `build-waveshare/PIOKMbox.uf2` 拖入该盘。
3. 复制完成后盘自动消失，板子重启进入固件。

也可用轮询脚本自动完成：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/flash_kmbox_windows.ps1
```

---

## 5. 使用与验证

接线方式：

- **鼠标/键盘** → 板子底部 USB-A 口
- **板子顶部 Type-C** → 电脑（电脑看到的就是你的鼠标/键盘本身，透传）

验证：

- 电脑设备管理器中出现你原来的鼠标/键盘（VID/PID 被镜像，看不到 RP2350）
- 鼠标可以直接操作电脑
- RGB 显示状态色（见下表）

### RGB 状态色

| 颜色 | 含义 |
|:---|:---|
| 蓝色 | 启动中 |
| 绿色 | 仅 USB Device 侧就绪 |
| 橙色 | 仅 USB Host 侧就绪 |
| 青色 | Device + Host 两侧均就绪 |
| 品红 | 鼠标已连接 |
| 黄色 | 键盘已连接 |
| 粉色 | 鼠标 + 键盘均已连接 |
| 红色 | 错误 |
| 紫色 | USB 挂起 |

---

## 6. 故障排查

| 现象 | 可能原因 | 解决 |
|:---|:---|:---|
| 鼠标插 USB-A 口完全无反应，RGB 也不亮 | 固件是按**其他板型**（如 Adafruit Metro RP2350）编译的，Host 引脚 GPIO32/33 在 RP2350A 上不存在 | 确认 `PICO_BOARD=waveshare_rp2350_usb_a` 后重新编译烧录 |
| RGB 颜色不对/不亮 | 板型的 NeoPixel 引脚配错（本板为 GPIO16） | 同上 |
| 电脑上看不到透传设备 | Type-C 线只能供电、无数据，或板子未启动 | 换带数据功能的 USB 线；确认 RGB 有点亮 |
| 开机时外设正常，运行中插拔不识别 | R13（1.5K D+ 上拉）未拆除 | 按[第 2 节](#2-️-热插拔注意r13-电阻)拆除 R13 |
| 编译报 `usbd_edpt_xfer` 参数错误 | SDK 中 TinyUSB 版本过新 | 见[第 3 节 TinyUSB 版本注意](#tinyusb-版本注意) |
| BOOTSEL 盘不出现 | 进 BOOTSEL 的操作不对 | 按住 BOOTSEL 再按 RESET；或按住 BOOTSEL 再插 USB 线 |

---

## 7. 相关文件

| 文件 | 说明 |
|:---|:---|
| `boards/waveshare_rp2350_usb_a.h` | 板级定义（芯片型号、Flash、默认引脚） |
| `CMakeLists.txt`（`waveshare_rp2350_usb_a` 分支） | 板级引脚配置（Host D+/D-、RGB 等） |
| `tools/build_kmbox_windows.ps1` | Windows 一键编译脚本 |
| `tools/flash_kmbox_windows.ps1` | BOOTSEL 轮询烧录脚本 |
