<div align="center">

# PIOKMbox

**USB HID 透传 & KMBox 串口接口 — 基于 RP2350**

[![Platform](https://img.shields.io/badge/platform-RP2350-blue?logo=raspberrypi&logoColor=white)](#硬件需求)
[![Language](https://img.shields.io/badge/language-C-555?logo=c&logoColor=white)](#开发)
[![License](https://img.shields.io/badge/license-open--source-green)](#许可证)
[![Protocol](https://img.shields.io/badge/protocol-KMBox%20B%20%2B%20%7C%20Ferrum%20%7C%20Macku-orange)](#kmbox-兼容性)

一款高性能双角色 USB HID 固件，可创建**透明 USB 透传设备**，同时提供 **KMBox 兼容的串口控制**，用于鼠标和键盘自动化，并支持高级拟人化以及通过 ILI9341 显示屏实现可选的视觉反馈。

```
鼠标/键盘 ──► [RP2350 开发板 1] ──► PC
                  ▲  UART（交叉连接）
                  ▼
              [RP2350 开发板 2] ──► ILI9341 TFT 显示屏
                  ▲
                  │ USB CDC
              [PC 工具 / 脚本]
```

</div>

---

## 目录

- [概述](#概述)
- [主要特性](#主要特性)
- [硬件需求](#硬件需求)
- [快速开始](#快速开始)
- [使用 KMBox 命令](#使用-kmbox-命令)
- [移动拟人化](#移动拟人化)
- [KMBox Bridge — 视觉反馈与自动瞄准](#kmbox-bridge--视觉反馈与自动瞄准)
- [架构设计](#架构设计)
- [状态指示](#状态指示)
- [开发](#开发)
- [性能指标](#性能指标)
- [故障排除](#故障排除)
- [贡献指南](#贡献指南)
- [许可证](#许可证)
- [致谢](#致谢)

---

## 概述

PIOKMbox 将 RP2350 开发板变成一个透明的中间人 USB HID 设备。你的 PC 看到的是原始鼠标或键盘——而不是微控制器——同时串口命令允许你在物理设备之外注入精确的、拟人化的输入。

| 功能           | 描述                                                                                                     |
|:---------------|:---------------------------------------------------------------------------------------------------------|
| **USB 透传**   | 镜像连接设备的 VID/PID、制造商和产品名称。PC 永远不会检测到 RP2350。                                     |
| **串口控制**   | 通过 UART 接受 KMBox、Macku 二进制和 Ferrum 兼容命令，注入鼠标移动、点击和键盘输入。                     |
| **拟人化**     | 运动感知抖动、速度抑制、过冲模拟、贝塞尔平滑——全部可在四个强度等级间配置。                               |
| **视觉反馈**   | 可选 ILI9341 TFT 显示屏，实时显示延迟图表、连接状态和温度指标。                                          |

> **散热提示：** 此固件运行在 240 MHz 以上以获得最佳性能。长时间运行时请监控温度，尤其是启用 TFT 显示屏时。

---

## 主要特性

- **透明 USB 透传** — PC 看到的是原始设备，而非 RP2350
- **KMBox 协议兼容** — 兼容现有 KMBox B+、Ferrum 和 Macku 工具
- **双核架构** — USB 主机和设备操作各使用专用核心
- **移动拟人化** — 4 种可配置模式（OFF / LOW / MEDIUM / HIGH），带自适应抖动
- **低延迟** — 二进制协议 < 50 µs，文本命令 < 100 µs
- **硬件看门狗** — USB 协议栈故障自动恢复
- **视觉状态** — NeoPixel RGB 反馈及可选 ILI9341 TFT 显示屏
- **Xbox 手柄支持** — GIP 协议透传

---

## 硬件需求

### 推荐配置

**双 Adafruit Metro RP2350 + ILI9341 显示屏**

#### 开发板 1：USB 代理（主 KMBox）

| 项目      | 详情                                        |
|:----------|:--------------------------------------------|
| **开发板** | Adafruit Metro RP2350                      |
| **角色**  | USB HID 透传 + KMBox 命令执行               |
| **USB-A** | 物理鼠标或键盘                              |
| **USB-C** | 连接 PC（显示为透传设备）                    |
| **UART**  | TX/RX 连接开发板 2（交叉），共地             |

#### 开发板 2：Bridge / 自动瞄准（可选）

| 项目      | 详情                                            |
|:----------|:------------------------------------------------|
| **开发板** | Adafruit Metro RP2350                          |
| **角色**  | 计算机视觉追踪 + ILI9341 显示屏驱动             |
| **USB-C** | 连接 PC（用于串口输入命令）                      |
| **UART**  | TX/RX 连接开发板 1（交叉），共地                 |
| **SPI**   | ILI9341 显示屏 + 可选触摸控制器                  |

#### ILI9341 TFT 显示屏（可选）

| 规格       | 值                                        |
|:-----------|:------------------------------------------|
| 分辨率     | 320 x 240                                 |
| 接口       | SPI（硬件加速）                            |
| 功能       | 实时延迟图表、状态显示、触摸支持           |

### 串口线连接

> **两块开发板之间的 UART 线必须交叉连接。**

```
开发板 1（代理）           开发板 2（Bridge）
    TX  ─────────────────►  RX
    RX  ◄─────────────────  TX
    GND ◄────────────────►  GND
```

### 供电

- USB 总线供电（5 V）
- 典型电流：150–300 mA（随显示屏变化）
- TFT 显示屏增加约 80–150 mA
- 无需外部电源

---

## 快速开始

### 1. 克隆并构建

```bash
git clone --recursive https://github.com/ramseymcgrath/RaspberryKMBox.git
cd RaspberryKMBox

# 如果已经克隆但未带 --recursive：
git submodule update --init --recursive

# 构建选项：
./build.sh metro          # Metro RP2350 主 KMBox
./build.sh bridge-metro   # Metro RP2350 Bridge（带显示屏）
./build.sh dual-metro     # 构建两个目标
./build.sh all            # 构建所有配置
```

### 2. 烧录固件

| 开发板                  | 步骤                                                                                                                       |
|:------------------------|:---------------------------------------------------------------------------------------------------------------------------|
| **开发板 1**（USB 代理）| 按住 **BOOTSEL** 同时连接 USB-C 到 PC。将 `build-metro/PIOKMbox.uf2` 拖入挂载的 **RP2350** 驱动器。                      |
| **开发板 2**（Bridge）  | 按住 **BOOTSEL** 同时连接 USB-C 到 PC。将 `bridge/build-metro/kmbox_bridge.uf2` 拖入挂载的 **RP2350** 驱动器。             |

两块开发板在烧录后会自动重启。

### 3. 连接开发板

以**交叉**方式连接 UART（TX→RX，RX→TX），并共地。参见上方[串口线连接](#串口线连接)。

显示屏接线请参阅 [`bridge/README.md`](bridge/README.md)。

### 4. 连接设备

1. **鼠标 / 键盘** → 开发板 1 的 USB-A 端口
2. **开发板 1 USB-C** → PC（透传设备）
3. **开发板 2 USB-C** → PC（串口输入命令）

### 5. 验证运行

- **NeoPixel** 根据连接设备变化颜色（参见[状态指示](#状态指示)）
- **鼠标 / 键盘** 应通过 PC 正常工作
- **显示屏** 显示连接状态和延迟（如已安装 bridge）
- **串口** — 开发板 1 通过 UART 接受 KMBox 命令

---

## 使用 KMBox 命令

### 连接参数

| 参数     | 值                                                     |
|:---------|:-------------------------------------------------------|
| 接口     | UART（硬件串口，开发板间交叉连接）                      |
| 波特率   | 115200（可配置；USB CDC 模式下不限速）                  |
| 协议     | KMBox 兼容的文本和二进制命令                            |

### 文本命令

```text
km.move(100, 50)      # 相对鼠标移动（+X 向右，+Y 向下）
km.left(1)            # 按下左键
km.left(0)            # 释放左键
km.click(0)           # 左键点击（0=左键，1=右键，2=中键）
km.wheel(5)           # 向上滚动（负值=向下）
km.lock_mx(1)         # 锁定 X 轴（忽略物理鼠标 X）
km.lock_my(1)         # 锁定 Y 轴（忽略物理鼠标 Y）
km.unlock_mx()        # 解锁 X 轴
km.unlock_my()        # 解锁 Y 轴
```

### 快速二进制协议

超低延迟（< 50 µs），使用 8 字节二进制数据包：

```python
# 快速鼠标移动（0x01 命令）
packet = bytes([0x01, x_lo, x_hi, y_lo, y_hi, buttons, wheel, 0x00])
serial.write(packet)
```

- 绕过文本解析以实现最低延迟
- 固定 8 字节数据包，时序可预测
- 支持 1000+ 命令/秒

### 监控模式

实时按键状态查询，用于自动化：

```text
km.monitor(1)         # 启用监控
km.isdown_left()      # 查询左键（返回 0 或 1）
km.isdown_right()     # 查询右键
km.isdown_middle()    # 查询中键
km.isdown_side1()     # 查询侧键 1
km.isdown_side2()     # 查询侧键 2
km.monitor(0)         # 禁用监控
```

### KMBox 兼容性

完全兼容 **KMBox B+**、**Ferrum** 和 **Macku** 协议：

| 功能                                        |   状态   |
|:--------------------------------------------|:--------:|
| 鼠标控制（移动、按键、滚轮）                 | 已支持   |
| 轴锁定（X/Y 移动、按键屏蔽）                 | 已支持   |
| 监控模式（实时按键状态）                      | 已支持   |
| 快速二进制协议（< 50 µs）                     | 已支持   |
| 平滑注入（速度匹配）                          | 已支持   |
| 移动拟人化（贝塞尔平滑）                      | 已支持   |

---

## 移动拟人化

先进的反检测系统，通过自适应抖动、速度抑制和过冲模拟来仿真自然的人类鼠标移动。所有功能均由硬件加速，每像素开销 < 10 个周期。

### 工作原理

**运动感知缩放** — 强度随移动距离自适应：

| 距离      | 抖动缩放 | 行为                                           |
|:----------|:---------|:-----------------------------------------------|
| 0–20 px   | 0.7–0.8x | 模拟精确定位时的手部颤抖                       |
| 20–60 px  | 0.3–0.7x | 精度与速度的平衡                               |
| 60–110 px | 0.1–0.3x | 有意图的移动，减少抖动                         |
| 110+ px   | 0.05–0.09x | 最小抖动——保持快速甩动的敏捷性               |

**速度抑制** — 随移动减速，抖动逐渐消退，防止移动完成后光标"发抖"。模拟自然的手部稳定过程。

**物理输入保护** — 拟人化仅作用于合成注入。物理鼠标和键盘输入原样透传，不受影响。

### 模式

通过按键（GPIO 7）或串口命令控制：

| 模式       | 抖动       | 过冲       | 启动延迟    | 使用场景                         |
|:-----------|:-----------|:-----------|:------------|:---------------------------------|
| **OFF**    | 无         | 禁用       | 无          | 测试、最高精度                   |
| **LOW**    | ± 0.06 px  | 禁用       | 0–1 帧      | 竞技游戏、快速反应               |
| **MEDIUM** | ± 0.17 px  | 5% 概率    | 1–3 帧      | **默认** — 通用                  |
| **HIGH**   | ± 0.33 px  | 10% 概率   | 2–6 帧      | 最大隐蔽性                       |

<details>
<summary><strong>详细模式参数</strong></summary>

**OFF** — 线性移动，无变化。最大 16 px/帧（固定）。最适合测试和高速自动化。

**LOW** — 传感器噪声底限处的微弱抖动，几乎不可感知。± 1% 传递误差。最大 15–17 px/帧（每次会话随机化）。累加器钳位：± 4 px。

**MEDIUM**（默认） — 匹配物理鼠标传感器噪声（约 ± 0.17 px）。± 2% 传递误差。最大 13–19 px/帧（每次会话随机化）。15–120 px 移动时有 5% 过冲概率（最大 0.5 px）。累加器钳位：± 3 px。

**HIGH** — 传感器噪声上限（约 ± 0.33 px）。± 3% 传递误差。最大 10–22 px/帧（每次会话随机化）。15–120 px 移动时有 10% 过冲概率（最大 1.0 px）。累加器钳位：± 2 px（最紧）。

</details>

### 其他技术

| 技术                       | 描述                                                                                                         |
|:---------------------------|:-------------------------------------------------------------------------------------------------------------|
| **贝塞尔平滑**             | 大幅度移动使用三次缓入缓出；快速修正使用二次缓出。根据移动特征自动选择。                                       |
| **微抖动**                 | ± 1–2 px 手部颤抖模拟。上下文感知（移动中段更多）。每帧 40% 概率。                                            |
| **过冲与修正**             | 5–10% 概率过冲 0.5–1.0 px，在 2–4 帧内平滑修正。仅在 > 15 px 的移动上生效。                                  |
| **每次会话随机化**         | 基础参数在初始化时变化。每次移动 ± 1 px，> 3 帧的移动 ± 1 帧。防止统计特征识别。                              |

### 按键控制（GPIO 7）

| 操作                      | 结果                                                   |
|:--------------------------|:-------------------------------------------------------|
| **短按**（< 3 秒）         | 切换拟人化模式。LED：红 → 黄 → 绿 → 青                |
| **长按**（≥ 3 秒）         | 重置 USB 协议栈                                       |

完整技术细节请参阅 [HUMANIZATION.md](HUMANIZATION.md)。

---

## KMBox Bridge — 视觉反馈与自动瞄准

可选的配套固件，用于第二块 **Adafruit Metro RP2350** 搭配 ILI9341 TFT 显示屏。提供实时视觉反馈和基于计算机视觉的自动瞄准功能。

```
┌──────────┐  USB CDC   ┌───────────────────┐  UART（交叉连接） ┌──────────────┐
│ PC 工具  │◄──────────►│  Metro RP2350     │◄────────────────►│ KMBox Metro  │
│（输入）  │            │ （Bridge/显示屏）  │                   │ （USB 代理） │
└──────────┘            └───────────────────┘                   └──────────────┘
                                │
                                ├── ILI9341 TFT（SPI）
                                └── 触摸控制器（可选）
```

### Bridge 功能

| 功能                       | 描述                                                       |
|:---------------------------|:-----------------------------------------------------------|
| **ILI9341 显示屏**         | 320 x 240 实时状态、延迟图表、连接指示灯                    |
| **USB CDC 接口**           | 接收 PC 串口命令，用于追踪和自动化                          |
| **颜色追踪**               | 硬件加速的色块检测和质心计算                                |
| **UART 中继**              | Bridge 与主 KMBox 之间的双向串口通信                        |
| **触摸支持**               | 可选 XPT2046 / FT6206 触摸控制器，用于交互控制              |
| **温度监控**               | 实时温度追踪，带可视化仪表                                  |

### Bridge 快速设置

1. `./build.sh dual-metro` — 构建两块开发板
2. 交叉连接 UART（TX→RX，RX→TX）+ 开发板间共地
3. 将 ILI9341 连接到 Bridge Metro 的 SPI 引脚（参见 [`bridge/README.md`](bridge/README.md)）
4. 烧录开发板 1：`build-metro/PIOKMbox.uf2`
5. 烧录开发板 2：`bridge/build-metro/kmbox_bridge.uf2`

---

## 架构设计

### 双核设计

```
┌─────────────────────────────────────────────────┐
│                   RP2350                        │
│                                                 │
│  ┌─────────────────┐   ┌─────────────────────┐  │
│  │     Core 0      │   │      Core 1         │  │
│  │                 │   │                     │  │
│  │  TinyUSB 设备   │   │  TinyUSB 主机       │  │
│  │ （HID → PC）    │   │ （PIO-USB ← 鼠标） │  │
│  │  KMBox 解析器   │   │  报告转发           │  │
│  │  平滑注入       │   │  VID/PID 缓存      │  │
│  └─────────────────┘   └─────────────────────┘  │
│           ▲                      │               │
│           └──── 共享内存 ────────┘               │
└─────────────────────────────────────────────────┘
```

1. **Core 1** 在 PIO-USB 上运行 TinyUSB 主机，与物理鼠标/键盘通信
2. 固件读取 HID 报告描述符，并缓存所连接设备的 VID/PID/字符串
3. **Core 0** 向 PC 暴露 TinyUSB HID 设备，镜像所连接设备的身份
4. VID/PID 变更时，设备重新枚举以反映新身份
5. 物理 HID 输入和 KMBox 串口命令通过智能轴锁定合并

### USB 透传

- **透明身份** — PC 看到的是原始鼠标/键盘，而非 RP2350
- **报告镜像** — 所有 HID 报告转发延迟 < 1 ms
- **动态重枚举** — 设备更换时自动适配
- **字符串描述符** — 镜像制造商和产品名称

### 串口命令注入

- **双路输入** — 物理输入和合成输入无缝共存
- **轴锁定** — 选择性 X/Y/按键过滤，实现精确控制
- **平滑注入** — 速度匹配的移动，帧级精确时序
- **优先级处理** — 物理输入优先；合成输入填充间隙

---

## 状态指示

### NeoPixel 颜色

| 颜色   | 状态                     |
|:-------|:-------------------------|
| 蓝色   | 启动中                   |
| 绿色   | 仅 USB 设备              |
| 橙色   | 仅 USB 主机              |
| 青色   | 两个 USB 协议栈均激活     |
| 品红   | 鼠标已连接               |
| 黄色   | 键盘已连接               |
| 粉色   | 鼠标 + 键盘已连接        |
| 红色   | 错误状态                 |
| 紫色   | 已挂起                   |

### 拟人化模式 LED

| 颜色   | 模式                    |
|:-------|:------------------------|
| 红色   | OFF（无拟人化）          |
| 黄色   | LOW（最小）              |
| 绿色   | MEDIUM（默认）           |
| 青色   | HIGH（最大）             |

### LED 模式

| 模式     | 含义                    |
|:---------|:------------------------|
| 快闪     | 设备已连接 / 活跃       |
| 慢闪     | 设备挂起或错误          |
| 常亮     | 正常运行                |

---

## 开发

### 项目结构

```
RaspberryKMBox/
├── PIOKMbox.c                # 主固件 — 核心编排
├── usb_hid.*                 # HID 设备/主机，VID/PID 镜像
├── kmbox_serial_handler.*    # KMBox UART 命令集成
├── smooth_injection.*        # 拟人化移动引擎
├── humanization_lut.*        # 预计算抖动查找表
├── led_control.*             # LED & WS2812 NeoPixel 控制
├── watchdog.*                # 硬件/软件看门狗
├── bridge_handler.*          # Bridge 通信协议
├── xbox_device.*, xbox_host.*# Xbox 手柄透传
├── ws2812.pio                # NeoPixel PIO 程序
├── defines.h, config.h       # 配置和引脚定义
├── lib/
│   ├── Pico-PIO-USB/         # PIO USB 库（子模块）
│   ├── kmbox-commands/       # KMBox 命令解析器
│   ├── fast-protocol/        # 二进制协议定义
│   ├── wire-protocol/        # 线路格式工具
│   ├── dma-uart/             # DMA 加速 UART
│   └── led-utils/            # LED 控制抽象
├── bridge/                   # Bridge 固件
│   ├── main.c                # Bridge 入口
│   ├── ili9341.c             # ILI9341 TFT 显示屏驱动
│   ├── latency_tracker.*     # 性能监控
│   ├── core1_translator.*    # CV 处理
│   ├── bridge_client.py      # Python 控制客户端
│   └── ferrum_translator.c   # Ferrum 协议支持
├── tools/                    # 开发工具
│   ├── generate_lut.py       # 生成拟人化查找表
│   ├── kmbox_stress_test.py  # 压力测试
│   └── logitech_hid_dump.py  # HID 设备分析
├── boards/                   # 开发板定义
│   └── adafruit_metro_rp2350.h
├── build.sh                  # 多目标构建脚本
└── CMakeLists.txt            # 构建配置
```

### 构建目标

```bash
./build.sh pico2            # RP2350（Pico 2）
./build.sh metro            # Metro RP2350（主 KMBox）
./build.sh bridge           # Bridge（XIAO RP2350）
./build.sh bridge-metro     # Bridge（Metro RP2350）
./build.sh dual-metro       # 两块 Metro 开发板
./build.sh all              # 所有配置
```

追加 `clean` 强制重新构建：`./build.sh all clean`

### 构建配置

在 `defines.h` 中定义的预设：

| 预设                       | 描述                     |
|:---------------------------|:-------------------------|
| `BUILD_CONFIG_DEVELOPMENT` | 默认 — 详细日志          |
| `BUILD_CONFIG_PRODUCTION`  | 优化，最少日志           |
| `BUILD_CONFIG_TESTING`     | 扩展诊断                 |
| `BUILD_CONFIG_DEBUG`       | 完整调试符号             |

### 时钟频率

| 目标                | 频率      | 备注                      |
|:--------------------|:----------|:--------------------------|
| 主 KMBox（RP2350）  | 300 MHz   | 针对 PIO-USB 优化         |
| Bridge              | 280 MHz   | 显示屏 + UART 均衡        |

### 前置条件

- [Pico SDK](https://github.com/raspberrypi/pico-sdk) 2.2.0+
- CMake 3.13+
- `arm-none-eabi-gcc` 14.2+
- Git（用于子模块）

---

## 性能指标

Metro RP2350 @ 300 MHz 的典型结果：

| 操作             | 延迟        | 备注                  |
|:-----------------|:------------|:----------------------|
| USB 透传         | < 1 ms      | 报告转发              |
| 文本命令         | < 100 µs    | 解析 + 执行           |
| 二进制命令       | < 50 µs     | 直接执行              |
| 拟人化开销       | < 10 周期   | 每像素计算            |
| 显示屏更新       | 16–33 ms    | 典型 30–60 FPS        |
| UART 传输        | 87 µs       | 8 字节 @ 115200 波特  |

---

## 故障排除

<details>
<summary><strong>USB 问题</strong></summary>

**设备无法识别：**
1. 确认 USB 主机端口有 5 V 供电
2. 检查 D+/D- 接线（GPIO 16/17）
3. 尝试更换 USB 线缆（部分线缆仅供电）
4. 检查调试 UART 的设备支持信息

**重枚举循环：**
- 通常由连接设备不稳定引起
- 检查 USB 线缆质量和供电稳定性
- 查看 GPIO 0/1 上的调试日志（115200 波特）

**透传不工作：**
- LED 应显示设备已连接状态
- 打开调试 UART 验证设备检测
- 具有复杂 HID 描述符的设备可能需要调整

</details>

<details>
<summary><strong>串口通信</strong></summary>

**KMBox 命令无响应：**
1. 确认 UART 线交叉连接（TX→RX，RX→TX）
2. 检查波特率（默认 115200）
3. 确保共地连接
4. 测试命令：`km.move(10, 10)`

**显示屏不更新：**
1. 验证 ILI9341 的 SPI 连接
2. 确认 Bridge 固件已正确烧录
3. 查看 Bridge 调试输出
4. 确认 TFT 供电（根据模块为 3.3 V 或 5 V）

</details>

<details>
<summary><strong>性能问题</strong></summary>

**高延迟：**
- 检查 CMakeLists.txt 中的 CPU 时钟频率
- 将拟人化模式设为 OFF 以获得最低延迟
- 监控温度（降频）
- 如使用 Bridge，降低显示屏刷新率

**移动感觉迟钝：**
- 尝试 OFF 或 LOW 拟人化模式
- 检查鼠标轮询率（推荐 1000 Hz）
- 确认物理鼠标传感器质量

</details>

<details>
<summary><strong>构建问题</strong></summary>

**CMake 错误：**

```bash
# 确保 Pico SDK 已安装并设置路径
export PICO_SDK_PATH=/path/to/pico-sdk

# 清理并重新构建
./build.sh metro clean
```

**烧录失败：**
- USB 连接时 firmly 按住 BOOTSEL 按钮
- 尝试更换 USB 端口或线缆
- 确认 .uf2 文件未损坏

</details>

---

## 高级用法

### 自定义拟人化配置

编辑 `humanization_lut.c` 创建自定义抖动配置。查找表基于移动距离定义抖动乘数。使用 `tools/generate_lut.py` 重新生成。

### 串口协议扩展

在 `lib/kmbox-commands/` 中扩展 KMBox 命令：

1. 定义命令结构
2. 在 `kmbox_serial_handler.c` 中添加解析器
3. 实现处理逻辑
4. 更新协议文档

### 显示屏定制

修改 `bridge/tft_display.c` 中的 Bridge 显示屏 — 配色方案、控件、刷新率和触摸控制。参见 [`bridge/README.md`](bridge/README.md) 了解显示屏 API。

---

## 贡献指南

欢迎贡献！请：

1. Fork 本仓库
2. 创建功能分支（`git checkout -b feature/amazing-feature`）
3. 在硬件上充分测试
4. 在代码和 README 中记录更改
5. 提交带有详细描述的 Pull Request

参见 [CONTRIBUTING.md](CONTRIBUTING.md) 了解开发指南。

---

## 许可证

主项目文件遵循标准开源实践。`lib/` 下的库保留其各自的许可证：

| 库           | 许可证                         |
|:-------------|:-------------------------------|
| Pico-PIO-USB | 见 `lib/Pico-PIO-USB/LICENSE`  |
| TinyUSB      | MIT                            |
| Pico SDK     | BSD 3-Clause                   |

---

## 致谢

- [Raspberry Pi Foundation](https://www.raspberrypi.org/) — Pico SDK 和文档
- [TinyUSB](https://github.com/hathach/tinyusb) — USB 协议栈
- [Sekigon-gonnoc](https://github.com/sekigon-gonnoc/Pico-PIO-USB) — Pico-PIO-USB
- [Adafruit](https://www.adafruit.com/) — RP2350 硬件
- KMBox 社区 — 协议文档

---

## 支持

| 渠道         | 链接                                                                                |
|:-------------|:------------------------------------------------------------------------------------|
| Bug 报告     | [GitHub Issues](https://github.com/ramseymcgrath/RaspberryKMBox/issues)             |
| 讨论区       | [GitHub Discussions](https://github.com/ramseymcgrath/RaspberryKMBox/discussions)   |
| 文档         | 参见各个 `.md` 文件了解详细主题                                                      |

---

<sub>本项目仅供教育和无障碍用途。用户有责任遵守适用的服务条款和法规。</sub>
