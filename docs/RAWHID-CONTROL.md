# RawHID 控制接口（SmartUniversalMouse 协议）

本文档说明 PIOKMbox 固件里 **RawHID 控制接口** 的设计、协议格式，以及它在 USB
描述符体系中的位置——这部分和"镶镜宿主鼠标接口"的逻辑耦合较深，容易在改动
描述符生成代码时踩坑，遇到问题时先看这里。

相关源码：`rawhid_control.h` / `rawhid_control.c`（协议实现）、`usb_hid.c`
（描述符生成、实例索引、回调分发）。

## 1. 用途

在镶镜宿主鼠标 HID 接口之外，额外挂一个 vendor-defined HID 接口，让 PC 端
客户端（colorant / SmartUniversalMouse 兼容客户端）不经 UART，直接通过 USB
HID 控制固件（移动、点击、按键、心跳、设备 UID、描述符/布局协商）。

- Usage Page：`0xFFC0`（Vendor Defined）
- Usage：`0x0C00`
- 仅一个 Interrupt IN 端点，**没有 Interrupt OUT 端点**——Output 报文全部走
  控制传输的 `SET_REPORT`（Windows hidapi 的写操作走这条路径；声明 Interrupt
  OUT 端点反而会让 Windows hidusb 判定接口失败，历史上试过，见第 4 节）。

## 2. 在 USB 描述符体系中的位置

固件会把宿主鼠标（以及它暴露的其它 HID 接口，若有）逐个"镶镜"到设备侧，
RawHID 控制接口**永远追加在所有镶镜接口之后**：

```
Interface 0..N-1  = mirrored_itfs[0..N-1]（宿主鼠标 + 其余宿主 HID 接口）
Interface N       = RawHID 控制接口          <- usbhid_get_rawhid_instance()
```

- `mirrored_itf_count`（`usb_hid.c`）：当前镶镜接口数量 N。
- `usbhid_get_rawhid_instance()`（`usb_hid.c:3397`）：返回 RawHID 的
  TinyUSB HID instance 号，恒等于 `mirrored_itf_count`（无鼠标时退化为 1，
  独立单接口模式下也是 1）。**这个值是动态的**——鼠标拔插、镶镜接口数量变化
  都会让 RawHID 的 instance 号跟着挪位（设备侧 `MI_XX` 编号也会变），
  `rawhid_control.c` 里所有访问 RawHID 的地方（`tud_hid_n_report`、
  `tud_hid_set/get_report_cb` 分支）都必须实时调用这个函数，不能缓存。
- 配置描述符由 `rebuild_configuration_descriptor()`（`usb_hid.c:3302`）
  统一重建：先按 `mirrored_itf_count` 循环写出镶镜接口，再追加一段
  RawHID 接口（`write_hid_interface_desc()`，无 OUT 端点）。
- Report Descriptor 回调 `tud_hid_descriptor_report_cb()`（`usb_hid.c:3202`）
  按同一套 instance 规则分发：`instance == usbhid_get_rawhid_instance()`
  返回 `desc_rawhid_control`，否则按镶镜表返回对应描述符。

## 3. 协议格式

### 3.1 Legacy 8 字节包

```
[0] = 0x5A magic
[1] = cmd
[2..6] = payload（5 字节）
[7] = checksum = XOR(byte0..6)，在混淆之前计算
```

发送前对 `byte[1..6]` 做 `XOR 0x3C` 混淆；接收时先解混淆再校验 checksum。

命令表（`rawhid_control.c` 顶部常量）：

| 命令 | 值 | 方向 | 说明 |
|---|---|---|---|
| `CMD_HANDSHAKE` | 0x01 | 主机→固件 | payload[0]=客户端协议版本，固件回 ACK 并按版本匹配置 `handshaked` |
| `CMD_ACK` | 0x02 | 固件→主机 | 握手应答，payload[0]=固件协议版本(0x02) |
| `CMD_MOVE` | 0x03 | 主机→固件 | payload: x(i16 LE) y(i16 LE) buttons_mask(1)，需已握手 |
| `CMD_CLICK` | 0x04 | 主机→固件 | payload[4]=按钮位掩码，逐位触发一次点击 |
| `CMD_PRESS` | 0x05 | 主机→固件 | payload[4]=按钮位掩码，逐位按下并保持 |
| `CMD_RELEASE` | 0x06 | 主机→固件 | payload[4]=按钮位掩码；掩码为 0 时释放所有已强制的按钮 |
| `CMD_HEARTBEAT` | 0x07 | 双向 | 主机 ping 或固件主动上报；回包=status,version,gen(LE),0 |
| `CMD_GET_DEVICE_ID` | 0x08 | 主机→固件 | 固件分两包回传 flash UID（每包 4 字节 + part 编号） |
| `CMD_PING` | 0xAB | 主机→固件 | 等价于 `CMD_HEARTBEAT` |

按钮位掩码：`0x01`=左键 `0x02`=右键 `0x04`=中键 `0x08`=侧键1 `0x10`=侧键2。

心跳状态位（`heartbeat_status()`）：`READY=0x01`
`MOUSE_CONNECTED=0x02` `HANDSHAKED=0x04` `REATTACHING=0x08`。

30 秒静默会被 `rawhid_control_task()` 判定为断线并重置协议状态
（`rawhid_control_reset()`：清 `handshaked`、释放所有强制按钮、清空发送队列）。

### 3.2 扩展帧（描述符暴露 + 布局协商）

用于客户端探测宿主鼠标真实的 HID Report Descriptor 并协商注入布局，
最大 64 字节，走同一个 Interrupt IN 端点：

```
[0]=0xA5 [1]=0x5A magic
[2]=version(0x01)
[3]=type（响应时 OR 0x80）
[4..5]=seq(LE)
[6]=payload_len(≤48)
[7..]=payload
[-2..-1]=CRC16-CCITT(MSB-first, init 0xFFFF, poly 0x1021)，覆盖 header+payload
```

| type | 说明 |
|---|---|
| `0x10 DESCRIPTOR_META` | 请求宿主鼠标描述符的 gen/len/crc/是否有效 |
| `0x11 DESCRIPTOR_CHUNK` | 按 offset 分片读取宿主鼠标原始 Report Descriptor（每片≤44字节） |
| `0x12 LAYOUT_BEGIN` | 客户端声明字段布局（report_id/wire_len/xy范围等），gen 必须与当前一致 |
| `0x13 LAYOUT_FIELD` | 逐字段确认（角色/bit offset/bit size），固件只做 gen 校验，不真正解析——注入引擎走自己的快速通道 |
| `0x14 LAYOUT_COMMIT` | 提交布局，gen 匹配后置 `layout_committed=true` |
| `0x15 INJECTION_STATUS` | 查询当前注入状态 |

`gen`（`usbhid_get_mouse_desc_generation()`）在每次宿主鼠标描述符重建时递增，
客户端据此判断是否需要重新拉取描述符——**协商内容仅用于客户端自检，固件的
实际按键/移动注入走独立的快速路径，不依赖协商结果**。

## 4. 故障排查记录：Code 10（CM_PROB_FAILED_START）

**现象**：Windows 设备管理器里 RawHID 控制接口对应的子设备（`MI_01` 或
`MI_02`，具体编号取决于镶镜接口数量）报 Code 10，Driver=`hidusb.sys`。
两台不同鼠标（不同 VID/PID）在**首次插入枚举**时就必现，与"同一设备重插"、
VID/PID 缓存、多核竞态都无关。

**排查路径**（避免下次重复走弯路）：
1. 先怀疑"配置描述符拓扑变化未触发重枚举"——`mirrored_itf_count` 变化时
   （鼠标插拔）如果 VID/PID 没变，Windows 可能持有旧拓扑缓存。这个问题确实
   存在，已经修复（见 `usb_hid.c` 里 `last_enumerated_mirrored_itf_count`
   相关逻辑），**但不是这次 Code 10 的根因**——新设备首次枚举根本不涉及缓存。
2. 逐字节核对 `write_hid_interface_desc()` 生成的 Interface/HID/Endpoint
   描述符字节布局，以及端点地址分配（`0x81+i`）——**语法完全正确**，排除。
3. 用 USBView 抓取真实设备的完整配置描述符：`bNumInterfaces=2`，
   Interface 1（RawHID）报表描述符声明长度 `0x18=24` 字节、`EP 0x82 IN`、
   无 OUT 端点——**和固件生成的字节完全吻合**，结构上无懈可击，排除"描述符
   语法/端点分配错误"。
4. 通过设备管理器"事件"标签页拿到 Windows 给出的**精确错误文本**：
   > HID 报表描述符未通过验证。声明的非常量主项没有相应的用法。
   （A declared non-constant main item has no corresponding usage.）

   这是 **HID Report Descriptor 语义校验**失败，不是字节语法问题——语法
   核对再仔细也查不出来，必须让 Windows 自己报错才能定位。

**根因**：`desc_rawhid_control[]`（`usb_hid.c` 约 572 行）只在 `Collection`
上声明了一个 `Usage(0x0C00)`，`Input` 和 `Output` 两个**非常量（Var）**主项
各自都没有自己的 `Usage`。HID 规范要求每个非常量主项必须有对应的 Usage
（可以是单个 Usage 复用到整组字段，也可以是 Usage Minimum/Maximum），
一个都不给会被 Windows 的 HID Parser 直接拒绝整个接口。

**修复**：在 `Input`/`Output` 前各插入一个局部 `Usage` 项
（`0x09,0x01` / `0x09,0x02`），对齐 Arduino RawHID（NicoHood HID-Project）
参考实现的标准写法：

```c
static const uint8_t desc_rawhid_control[] = {
    0x06, 0xC0, 0xFF,  // Usage Page (Vendor Defined 0xFFC0)
    0x0A, 0x00, 0x0C,  // Usage (0x0C00)
    0xA1, 0x01,        // Collection (Application)
    0x15, 0x00,        //   Logical Minimum (0)
    0x26, 0xFF, 0x00,  //   Logical Maximum (255)
    0x75, 0x08,        //   Report Size (8)
    0x95, 0x40,        //   Report Count (64)
    0x09, 0x01,        //   Usage (0x01)   <- 新增：Input 需要自己的 Usage
    0x81, 0x02,        //   Input (Data, Var, Abs)
    0x95, 0x40,        //   Report Count (64)
    0x09, 0x02,        //   Usage (0x02)   <- 新增：Output 需要自己的 Usage
    0x91, 0x02,        //   Output (Data, Var, Abs)
    0xC0               // End Collection
};
```

长度从 24 字节变为 28 字节；所有引用处都用 `sizeof(desc_rawhid_control)`，
无需改动配置描述符构建逻辑，长度会自动传播。

**经验教训**：HID Report Descriptor 的字节语法正确（能被任意 short-item
解析器无异议地解析）不代表语义正确。**每个非常量（Var）主项都必须有对应
Usage** 这条规则很容易在手写 vendor 描述符时漏掉，且几乎没有工具能在
"发给 Windows 之前"帮你查出来——最快的定位方式就是直接看 Windows 设备管理器
"事件"标签页给出的原始错误文本，而不是反复用工具核对字节。

## 5. 运行时诊断通道（排障用，问题解决后可整段删除）

`usb_hid.c` 里保留了一段用于定位本次问题的诊断代码
（搜索 `rawhid_diag_`），通过在 **itf0**（无镶镜时是独立键鼠接口，有镶镜时
是镶镜鼠标接口）上发起：

```
GET_REPORT, report_type = Input 或 Feature, report_id = 0xAA
```

回读 8 字节：`[0]=0xD1` `[1]`=RawHID report descriptor 被
`GET_DESCRIPTOR` 请求过的次数 `[2]`=`usbhid_get_rawhid_instance()`
运行值 `[3]`=`mirrored_itf_count` 运行值 `[4]`=状态位掩码
`[5]`=GET_REPORT 调用次数 `[6]`=itf0 report descriptor 请求次数
`[7]=0xA5`。用于确认"Windows 到底有没有走到读取 RawHID 描述符这一步"，
不影响正常协议收发（用了不会和真实 `REPORT_ID_KEYBOARD(1)` 冲突的
`0xAA` 作为探测 report id）。当前 Code 10 问题已确认修复，这段代码
不再需要，后续清理时可以整段删除（`rawhid_diag_*` 四个计数器 +
`tud_hid_get_report_cb` 里的诊断分支）。
