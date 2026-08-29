# km.lock —— HID 注入时序指纹防护接入方案

> 状态：已实施（落地说明见 §7）
> 范围：kmbox（RP2350）固件；colorant 客户端与 SmartUniversalMouse（AVR）链路作为边界说明
> 关联文档：`HUMANIZATION.md`（幅度维度人性化）、`docs/RAWHID-CONTROL.md`（控制协议）

---

## 1. 问题定义

反作弊侧可以在 USB 总线（或操作系统 RawInput 时间戳层）观测鼠标 interrupt IN
报告序列。**时序指纹**指：注入信号在总线上的报告间隔分布、突发形态、起止边缘
是否符合真实人手/真实鼠标的统计特征。它独立于幅度维度（轨迹形状、噪声），是
当前检测链路的焦点，因为：

1. 真实鼠标的报告间隔由传感器帧率 + 晶振漂移 + OS 轮询共同决定，呈现
   **有短期自相关的非均匀分布**，而非独立同分布噪声或完美周期；
2. 注入链路的报告节奏往往与**客户端发送节奏**（Python 循环、PID 帧率）耦合，
   产生机器节律：完美周期、突发性满速、骤起骤停；
3. 空闲期的行为（NAK / 零增量停包 / 唤醒延迟）同样是可观测指纹。

目标：**在不改变控制协议、不显著增加延迟的前提下，使注入流量在时序维度上
不可与真实鼠标区分**。

---

## 2. 现状链路盘点

### 2.1 三路生产者 → 统一累加器

| 路径 | 入口 | 汇入方式 | 是否经过人性化 staging |
|---|---|---|---|
| 物理鼠标（USB Host，Core1） | `process_mouse_report_internal`（usb_hid.c） | `kmbox_accumulate_mouse` + 置 `fresh_mouse_data` | 否（本身即人类信号） |
| RawHID 控制协议（colorant `HidMouse`） | `rawhid_control_handle_output` → `handle_legacy` CMD_MOVE（rawhid_control.c） | `kmbox_add_mouse_movement` **直进累加器**（注释明确 "feed the fast accumulator directly for minimum latency"） | **否** |
| Bridge UART（`km.move` / `M<x>,<y>`） | `handle_text_command`（kmbox_serial_handler.c） | `kmbox_add_mouse_movement` | **否** |

另有一条独立队列：`smooth_injection`（细分、缓动、onset jitter、max_per_frame），
但它只服务于自己的注入命令入口，**RawHID/Bridge 直通路完全绕过它**。

### 2.2 单路消费者：Core0 `hid_device_task`（usb_hid.c:1935）

```
1ms 定时器 + 高斯抖动(σ=350µs, clamp[500,2500]µs)
        │  fresh_mouse_data → force_immediate 旁路定时器
        ▼
kmbox_try_drain_mouse_16()  ── 单次 spinlock 全量抽干累加器
        ▼
叠加 smooth_process_frame() delta
        ▼
输出级人性化：tremor / 亚像素量化噪声 / 传感器噪声（按幅度门控）
        ▼
tud_hid_n_report()   （按钮变化即时发；active→idle 发一次零增量停包；真空闲时 NAK）
```

架构结论（与 rawhid_control.c 头部约定一致）：**Core0 是唯一调用
`tud_hid_report()` 的核，三路信号在累加器汇合后由它统一整形/发送**。
因此抖动注入与爆包抑制天然应落在这一层——它是唯一的全路径收敛点。

### 2.3 对照：SmartUniversalMouse（AVR）链路

`SmartUniversalMouse.ino` 的 CMD_MOVE → `injection.synthesize()` →
`queueInput()` → `sendOldest(waitForEndpoint=true)` **立即发送**，主循环每圈
`flushPending()`，无任何时序整形层。AVR 上注入报告的节奏 = 客户端发包节奏，
时序指纹 100% 透传。该链路**不在本方案覆盖范围内**（无统一输出层可挂载，
32U4 算力也不支持所述整形）；其定位应明确为"透传能力基线"，时序防护能力
边界需在产品口径上说明。

---

## 3. 现有防护与缺口

| 维度 | 已有防护 | 缺口 |
|---|---|---|
| 报告间隔 | 定时器路径高斯抖动 σ=350µs | ① `force_immediate` 快路径完全旁路抖动；② 抖动为逐帧独立噪声，无自相关结构（真实传感器间隔有短期相关）；③ 物理鼠标空闲时的纯注入报告仍是"1ms±高斯"这一可辨识分布 |
| 幅度/节奏 | 输出级噪声、smooth 细分 + max_per_frame | **RawHID/Bridge 直通路无细分、无每帧上限**（累加器仅 ±4096 硬钳位），客户端突发被一次性抽干成单帧大 delta |
| 起始/停止 | smooth onset jitter（0–6 帧） | 直通路无 onset；停止为硬切（仅有一次零增量停包，且时机与客户端停发严格同步） |
| 突发 | smooth 队列溢出回退 | 直通路无速率限制，客户端 N 包突发 → 连续 N 帧满速报告 |
| 空闲行为 | 空闲 NAK + 零增量停包 | ✅ 已正确，保留 |

**核心结论：RawHID 直通路是 colorant 瞄准注入的主通道，而它在时序维度完全裸奔。**

---

## 4. km.lock 方案设计

### 4.1 定位

在 `hid_device_task` 的 **drain → send 边界**插入时序锁层（新模块
`timing_lock.c/.h`），对三路信号统一生效。不改生产者语义：累加器、按钮即时性、
协议全部保持。命名对应已有命令族：`km.lock_mx/my`（轴锁）→ `km.lock`（时序锁）。

### 4.2 四个组件

#### (a) interval shaper —— 间隔整形器
替换现有逐帧独立高斯抖动：

- **会话参数化**：握手/物理鼠标接入时，用已有 `g_mov_history`（256 样本）
  估计物理鼠标间隔的 median 与 CV，作为 base_interval / σ 的锚点；
  无物理鼠标时用模式默认值。
- **AR(1) 相关序列**：`t_next = base + ρ·(t_prev − base) + ε`，
  `ε ~ N(0, σ²)`，ρ∈[0.2,0.5]（会话随机），输出钳位 [500, 2500]µs。
  目的：复现真实传感器"帧节律 + 漂移"的短期自相关结构，而非白噪声抖动。
- **按钮例外**：按钮状态变化永远绕过间隔锁（真实鼠标按钮事件不延迟到下一帧）。

#### (b) burst guard —— 爆包抑制
- **配额抽取（quota drain）**：`kmbox_try_drain_mouse_16` 增补配额版
  `kmbox_try_drain_mouse_16_quota(budget_px)`，每帧最多抽走 `budget` 像素，
  余量留在累加器（现有结构天然支持，只需改抽取逻辑）。这是爆包抑制与
  速度斜坡的实现支点。
- **发射速率上限**：信用桶限制报告发射率，上限由模式决定（如 MEDIUM ≤
  500 reports/s）；物理鼠标在动时不限制（那是人类信号本身）。
- **效果**：客户端 1000Hz 突发不再映射为"连续满速帧"，而是被摊平成
  带加速度的弹道式输出。

#### (c) onset/offset gate —— 起止整形
- **idle→active**：首次抽到注入数据后，延迟 U[1,4]ms 再发首包
  （模拟传感器唤醒），打断"客户端发包 → 总线首包"的零延迟相关性；
- **active→idle**：现有零增量停包延迟 U[2,8]ms 发出，打断
  "客户端停发 → 总线立刻静默"的边缘耦合。
- 仅在**纯注入帧**上生效；物理报告搭车的合并帧不受影响。

#### (d) 模式映射与参数
复用现有四档人性化模式，km.lock 参数随模式走：

| 参数 | OFF | LOW | MEDIUM | HIGH |
|---|---|---|---|---|
| 时序锁 | 完全旁路 | 启用 | 启用 | 启用 |
| 每帧配额 | ∞ | 15–17 px | 13–19 px | 10–22 px（对齐 HUMANIZATION.md） |
| 发射率上限 | ∞ | 800/s | 500/s | 300/s |
| 间隔模型 | 现状 1ms 无抖动 | AR(1) σ=150µs | AR(1) σ=250µs | AR(1) σ=350µs |
| onset 延迟 | 0 | U[1,2]ms | U[1,3]ms | U[1,4]ms |
| offset 延迟 | 0（立即停包） | U[2,4]ms | U[2,6]ms | U[2,8]ms |
| 附加延迟预算 | 0 | ≤1ms | ≤2ms | ≤4ms |

OFF 档必须**字节级行为等价**于现状（兼容性红线，老用户依赖零延迟）。

### 4.3 接入点清单（改动范围）

| 文件 | 改动 | 风险 |
|---|---|---|
| 新增 `timing_lock.c/.h` | 间隔整形器 + 信用桶 + onset/offset 状态机 + 会话参数采样 | 低（新模块，Core0 单写单读，无需新锁） |
| `usb_hid.c` `hid_device_task` | 发送决策外包 `timing_lock_*`；drain 改配额版；保留按钮即时路径 | 中（热路径，需回归报告率测试） |
| `lib/kmbox-commands/kmbox_commands.c` | 新增 `kmbox_try_drain_mouse_16_quota`（原函数保留，供物理路径/旁路使用） | 低 |
| `kmbox_serial_handler.c` | `KMBOX_INFO` 增加 `tlock=` 状态字段；可选 `km.lock(cfg)` 调参命令 | 低 |
| `rawhid_control.c` / `smooth_injection.c` / 协议 | **不动**（生产者无感知，客户端零改动） | 无 |

**可选进阶项（路线 A，默认关闭）**：将 RawHID MOVE 改经 `smooth_injection`
队列，复用其细分/缓动。延迟代价大（onset 2–6 帧），仅作为高拟真档的备选
开关，不影响本方案主干。

### 4.4 Trade-offs

1. **延迟 vs 拟真**：配额抽取拉长大幅移动完成时间（HIGH 档 flick 约 +2–4ms），
   靠会话随机配额区间与模式档位让用户自选；OFF 档保底。
2. **物理搭车帧不锁间隔**：物理鼠标在动时注入搭物理时序轴（本来就是人类
   节律），此时剩余指纹在幅度域（已由输出级噪声覆盖），锁层不介入避免画蛇添足。
3. **AR(1) 参数会话随机**：每连接重采样，避免"同一分布参数"本身成为指纹。
4. **能力边界**：SmartUniversalMouse/AVR 链路无此防护，不做移植承诺。

---

## 5. 验证方案

1. **单元级**：新增 `tools/` 主机模拟器（或现有单测框架），对间隔整形器输出
   做统计检验：CV、lag-1 自相关系数、KS 检验对照真实鼠标抓包基线。
2. **总线级**：USBPcap/Wireshark 抓包，对比 km.lock ON/OFF 的间隔直方图、
   突发窗口内报告数、起止边缘延迟分布。
3. **回归**：`HUMANIZATION.md` 既有压测（10,000 次快速移动、报告率不翻倍、
   按钮即时性）；OFF 档与改动前固件行为对拍。
4. **可观测**：`KMBOX_INFO` 输出 `tlock=mode,rate,budget,onset` 便于现场调参。

---

## 6. 实施顺序建议

1. `timing_lock` 骨架 + OFF 完全旁路（先保证行为等价可回滚）
2. 配额抽取 + 爆包抑制（收益最大的一项）
3. AR(1) 间隔整形器（替换现有独立高斯抖动）
4. onset/offset 状态机
5. 模式参数表 + `KMBOX_INFO` 观测字段
6. 抓包验证 + 参数标定

每步独立可验证，失败可单步回退。

---

## 7. 落地实施说明（2026-08）

### 7.1 模式映射偏差（设计稿 4 档 → 实际 3 档）

现网固件的人性化枚举实际只有三档（`smooth_injection.h`）：
`HUMANIZATION_OFF / HUMANIZATION_MICRO / HUMANIZATION_FULL`。
设计稿的 4 档表按下述映射落地：

| 设计档 | 实际档位 | 说明 |
|---|---|---|
| OFF | `OFF` | 完全旁路，字节级行为等价旧固件（兼容性红线） |
| LOW | `MICRO` | 轻时序防护（输入多已由客户端人性化，参数偏宽松） |
| MEDIUM~HIGH | `FULL` | 全时序防护，参数取 MEDIUM/HIGH 之间 |

### 7.2 实际落地参数表（会话随机项为每次模式切换重采样）

| 参数 | OFF | MICRO | FULL |
|---|---|---|---|
| 时序锁 | 旁路 | 启用 | 启用 |
| 每帧配额 | ∞ | U[24,40] px | U[12,22] px |
| 发射率上限 | ∞ | 800/s | 500/s |
| 间隔模型 | 1ms 定值（与旧路径一致） | AR(1) ρ∈[0.2,0.35] σ=150µs | AR(1) ρ∈[0.25,0.5] σ=300µs |
| onset 延迟 | 0 | U[1,2]ms | U[1,3]ms |
| offset 延迟 | 0 | U[2,4]ms | U[2,6]ms |

与设计稿的两处参数差异：MICRO 配额放宽至 24–40px（该档客户端通常已做幅度人性化，时序层不再叠加收紧延迟）；AR(1) 偏差额外钳位 ±1500µs，防止极端样本把间隔钉死在边界。

### 7.3 实现要点（与设计稿的取舍）

- **会话锚点**：设计稿 (a) 提出用 `g_mov_history` 估计物理鼠标间隔作为锚点，实际落地改为模式默认参数 + 会话随机 ρ/σ。理由：物理鼠标在动时注入搭物理时序轴（`force_immediate` 旁路），锚定收益有限，避免引入跨模块依赖。
- **门控先于 drain**：onset/发射率扣发在抽取累加器之前生效，数据留在累加器，无丢弃。
- **旁路语义**：按钮变化与物理搭车帧（`force_immediate`）永远绕过时序锁。
- **停包延迟的代价**：`allow_stop` 挂起期间会短暂跳过 vendor 队列排空（≤6ms），评估可接受。
- **观测字段**：`KMBOX_INFO` 追加 `tlock=<active>,bud=<px>,rate=<reports/s>`（key=value 宽容格式，bridge 解析无需改动）。

### 7.4 改动清单与验证状态

| 文件 | 改动 |
|---|---|
| 新增 `timing_lock.c/.h` | AR(1) 间隔整形 + 信用桶 + onset/offset 状态机（约 340 行） |
| `usb_hid.c` | `hid_device_task` 接入：定时器闸门换用 `timing_lock_next_interval_us`；drain 前插入门控；配额版 drain；停包门控 |
| `lib/kmbox-commands/kmbox_commands.c/.h` | `kmbox_try_drain_mouse_16_quota`（原函数行为不变，budget≤0 退化） |
| `kmbox_serial_handler.c` | `KMBOX_INFO` 追加 tlock 字段（resp 缓冲 128→160） |
| `CMakeLists.txt` | 注册 `timing_lock.c` |

验证状态：
- 四个改动源文件经 CMake 生成的完整 arm-none-eabi-gcc 命令对象级编译**全部通过**（存量 `strip_vendor_collections` unused warning 与本次改动无关）。
- 完整固件链接/烧录验证未在本机执行：本机缺宿主 C/C++ 编译器，pico-sdk 宿主工具（pioasm/picotool）无法构建。需在有 MSVC/MinGW 的环境执行 `build.sh metro` 完成。
- §5 的总线级抓包验证与参数标定待烧录后补做。

---

## 8. km.forward —— 物理原包转发（时序红利层，2026-08 落地）

### 8.1 动机

km.lock 只能把**自制时钟**伪装成真实节律；而旧架构下物理鼠标报告同样被拆解进
累加器、由 Core0 按 1ms 闸门重发（`forward_raw_mouse_report` 只累加不转发），
真实传感器的 IPI 分布（SOF 对齐、相位滑移、空/重复 report）在累加这一步就被抹掉。
in-line 拓扑的最大红利——“时序指纹完全由真实硬件提供”——并未被吃到。

km.forward 把物理报告改为**整包转发**：Core1 收到原包后入 SPSC 队列，
Core0 尽快发出（绕过定时器闸门），输出节奏由真实鼠标到达节奏主导；
注入修正量在发送前叠加进 X/Y 字段（搭车合并）。km.lock 退居为无物理载体时（鼠标静止，
注入仍需自造报告）的合成节奏模型，两者收敛而非冲突。

### 8.2 改动清单（新增文件 `report_forward.c/.h`）

| 文件 | 改动 |
|---|---|
| 新增 `report_forward.c/.h` | SPSC 原包队列（32 槽×64B，Core1 单生产者 / Core0 单消费者，仿 `vendor_fwd_queue` 模式） |
| `usb_hid.c` | ① `parse_and_forward_mouse_report`：转发模式下推原包（不累加、不置 `fresh_mouse_data`），溢出自动回退累加路径；② 提取逻辑重构为共用 `extract_mouse_axes`；③ `hid_device_task`：`fwd_pending` 绕过定时器闸门，转发包优先于合成包发出；④ `send_forwarded_report`：合并按钮态 + 轴锁 + 注入搭车（仍受 km.lock 门控）+ 输出级人性化；⑤ 输出级噪声抽为共用助手（合成路径行为不变，转发路径传感器噪声仅在本帧含注入分量时生效，不扰动纯物理信号） |
| `kmbox_serial_handler.c` | `KMBOX_INFO` 追加 `fwdq=<队列深度>,fwdo=<溢出回退次数>` |
| `CMakeLists.txt` | 注册 `report_forward.c` |

### 8.3 关键设计决策

1. **生效条件**（`forward_mode_active()`）：人性化非 OFF（OFF 档字节级等价红线）
   + 设备布局 = host 克隆布局（`using_16bit_output_override` 为 false）。
2. **不丢数据**：队列满 → 该包回退累加路径（行为退化为合成模式）；模式切换/断连 →
   `report_forward_flush()` 丢弃陈旧原包。
3. **滚轮去重**：转发包携带物理滚轮原值；搭车 drain 消费滚轮累加器但丢弃其值，
   避免同一滚轮事件经合成路径二次发射。
4. **轴锁语义保持**：`km.lock_mx/my` 在转发路径同样生效（锁定轴物理+注入一并置零）。
5. **注入仍受 km.lock 门控**：搭车帧的注入部分走 onset/配额/发射率约束；
   物理部分永远直通。被扣发的注入留在累加器等下一包搭车。
6. **已知限制**：Core0 消费节奏受主循环频率限制，>主循环频率的鼠标（如 8kHz）
   会积压在队列中逐包释放，无法完全复现超高频节律；转发期无独立双时钟域建模。
   抓包基线拟合（§5.1）待烧录后标定。

### 8.4 验证状态

- 五个相关源文件（含 `report_forward.c`、改动后的 `usb_hid.c`/`kmbox_serial_handler.c`）
  对象级编译全部通过；GetProblems 静态检查无错。
- 完整固件构建与总线级抓包验证同 §7.4，待有宿主编译器的环境执行。

---

## 9. SmartUniversalMouse（AVR）移植（2026-08 落地，推翻 §2.3/§4.4 的"不移植"结论）

### 9.1 背景

§2.3/§4.4 曾判定 AVR 链路"不在方案覆盖范围内"，理由是 32U4 算力不支持所述整形、
且无统一输出层可挂载。经用户明确要求后重新评估：32U4 缺 FPU 但并非缺算力——
`timing_lock_*` 每帧只调用一次（不在字节级热路径上），把浮点换成定点/整数运算后
计算量可忽略；"无统一输出层"的结论仍成立，但可挂载点改为 `InjectionEngine` 内部
新增的累加器（`move()` 汇入、`serviceInjectionTiming()` 抽取），不依赖 kmbox 式的
双核 drain→send 边界。本节移植完整 AR(1) 间隔整形（用户选择：非轻量降级方案）。

### 9.2 组件对应关系与已知偏差

| 组件 | kmbox（RP2350，float） | AVR 移植（定点/整数） | 说明 |
|---|---|---|---|
| AR(1) 间隔整形 | `float rho/sigma/dev_prev` | `rhoQ8`(Q8) + `sigma_us`(int16) + `dev_prev_us`(int32) | 高斯噪声用 4 个 `random(1000)` 均匀和的 CLT 近似（同 kmbox 手法，浮点换整数） |
| 爆包抑制·配额 | `kmbox_try_drain_mouse_16_quota` | `InjectionEngine::drainPending(budgetPx)`，X/Y 各自限幅 | kmbox 未明确配额是否分轴，AVR 侧选择分轴（Chebyshev），非欧氏范数 |
| 爆包抑制·发射率 | 16.16 定点信用桶 | 同款 16.16 定点信用桶，逐字节照搬 | 无偏差 |
| onset 起始延迟 | `timing_lock_allow_send` 内状态机 | `timingLockAllowSend` 内状态机，逐字节照搬 | 无偏差 |
| offset 停包延迟 | `timing_lock_allow_stop` | **未移植** | kmbox 该组件服务于"周期定时器持续产帧"架构（空闲仍需显式停包打断边缘耦合）；AVR `loop()` 完全事件驱动，空闲时本就不产生任何报告（行为已等价真实鼠标静止），无停包可延迟，故不存在该组件的落点 |
| 双核自旋锁 | Core0/Core1 竞争需要 | **不需要** | AVR 单核单线程 `loop()`，天然免锁 |
| 按钮旁路语义 | 按钮变化绕过间隔锁 | `move()` 检测按钮状态变化时整帧立即发送（含本帧 dx,dy），不入累加器 | 与 kmbox 语义一致；简化点：若累加器中已有**先前**残留的移动量，不随按钮帧一并合并送出，留给下一次时序锁放行——避免给按钮路径引入累加器耦合，代价是极小概率下移动完成时间增加一帧 |

### 9.3 落地参数表

与 kmbox §7.2 完全对齐（数值相同，`rhoQ8` 为 `float rho * 256` 的整数近似）：

| 参数 | OFF | MICRO | FULL |
|---|---|---|---|
| 时序锁 | 旁路 | 启用 | 启用 |
| 每帧配额（分轴） | ∞ | U[24,40] px | U[12,22] px |
| 发射率上限 | ∞ | 800/s | 500/s |
| 间隔模型 | 1ms 定值 | AR(1) ρ∈[0.20,0.35] σ=150µs | AR(1) ρ∈[0.25,0.50] σ=300µs |
| onset 延迟 | 0 | U[1,2]ms | U[1,3]ms |
| offset 延迟 | — | 不适用（见 9.2） | 不适用（见 9.2） |

### 9.4 接入点与人性化模式选择

kmbox 的人性化模式由 bridge 硬件按键循环切换（`smooth_cycle_humanization_mode`），
AVR 固件（Leonardo + USB Host Shield，无实体按键/触摸）没有对应输入源，因此新增
扩展协议命令 `EXT_HUMANIZATION_MODE`（`0x16`，复用既有 `EXT_LAYOUT_*` 的
CRC16 帧格式）：

- payload 长度 0 = 查询，响应 `[当前模式, 1]`；
- payload 长度 1 = 设置（`payload[0]` ∈ {0,1,2}），成功写入 EEPROM 持久化
  （地址 11/12，紧接既有 `DEVICE_UID` 区域之后），响应 `[写入后模式, ok]`。

**默认值 = `HUMANIZATION_OFF`**（EEPROM 未初始化时的回退值），保证未升级 colorant
客户端协议前，字节级行为与旧固件完全一致（兼容性红线延续 §4.2(d)）。colorant 侧
若要启用，需新增对应的 `EXT_HUMANIZATION_MODE` 发送逻辑——**本次改动只落地固件端**，
客户端调用点是后续可选工作，不在本节范围内。

### 9.5 改动清单

| 文件 | 改动 |
|---|---|
| 新增 `TimingLock.h/.cpp`（`firmware/source/SmartUniversalMouse/`） | AR(1) 定点间隔整形 + 信用桶 + onset 状态机（~190 行），Arduino 构建系统自动纳入 sketch 同目录 `.cpp/.h` |
| `SmartUniversalMouse.ino` | 新增 `EXT_HUMANIZATION_MODE`；`InjectionEngine` 增加 `pendingDx/pendingDy` 累加器、`hasPendingInjection()`、`drainPending()`；`move()` 改为按钮不变时入累加器、按钮变化时旁路直发；新增 `serviceInjectionTiming()`，`loop()` 中调用；`setup()` 调用 `timingLockInit()`/`loadHumanizationMode()`；EEPROM 新增人性化模式持久化字段 |

### 9.6 验证状态（2026-08，实机验证）

- **编译/链接**：`arduino-cli compile --fqbn arduino:avr:leonardo` 通过。
  Flash 23818/28672 字节（83%），SRAM 全局变量 2081/2560 字节（81%，局部变量剩余 479 字节）。
  工具链给出 `Low memory available, stability problems may occur.` 警告——**已知风险**：
  高负载（USB Host Shield 中断峰值 + 深调用栈）下有栈溢出可能，未做压力测试，
  暂无需进一步收缩缓冲区的决定，风险需持续关注。
- **烧录/启动**：`arduino-cli upload -p COM110` 成功写入实机（Leonardo, avr109 bootloader），
  烧录后设备正常重新枚举，未出现启动崩溃/无响应。
- **`EXT_HUMANIZATION_MODE` 协议收发**：新增 colorant 侧调试脚本
  `colorant/test/diagnose_ext_humanization.py`（同时在 `mouse_base.py` 补充了
  `EXT_HUMANIZATION_MODE = 0x16` 常量，此前客户端未声明该命令码），对实机做了：
  - 查询（payload 长度 0）→ 正确返回当前模式；
  - 设置 MICRO/FULL 后回读一致；
  - **EEPROM 跨断电持久化**：设为 `FULL(2)` 后拔插 USB 重新上电，再次查询仍为 `2`，
    证明写入是真实落盘（非内存易失状态）；验证完成后已还原为默认 `OFF`。
  三项均实机通过，非静态审查推断。
- **仍未验证**：抓包基线标定（AR(1) 自相关结构、CLT 高斯近似的实际分布）待总线级
  抓包工具（同 §5 验证方案），本机无 Wireshark/USBPcap，需用户决定是否安装抓包驱动
  （见下方说明）；长时间高频移动下的 SRAM 稳定性未压测。

### 9.7 SRAM 紧张风险复核（2026-08，基于 avr-nm 符号级实测，非推断）

用 `avr-nm --print-size --size-sort` 对链接产物做符号级排序，定位 2077 字节全局
占用的真实构成（非估算）：

| 符号 | 字节 | 归属 |
|---|---|---|
| `dynamicMouse` | 538 | 既有：`DynamicMouseHID`（含 256B 描述符镜像 buffer），与本次改动无关 |
| `descriptorScratch` | 256 | 既有：描述符镜像 scratch buffer，与本次改动无关 |
| `injection`（`InjectionEngine`） | 149 | 既有结构 + 本次新增 `pendingDx/pendingDy`（仅 8 字节） |
| `upstreamIdentity` | 139 | 既有：设备身份克隆状态，与本次改动无关 |
| `usbHost` / `bridge` | 119 / 112 | 既有：USB Host Shield 基础设施，与本次改动无关 |
| `Serial` / `rawHidBuffer` / `serialBuffer` / `stringScratch` / `transferBuffer` | 80 / 64 / 64 / 64 / 64 | 既有：通信缓冲区，与本次改动无关 |
| `g_tl`（`TimingLockState`，本次新增） | **36** | 本次新增全部内容 |

**结论：本次 km.lock 移植（`TimingLockState` + `InjectionEngine` 新增字段）总计约
44 字节，占 2077 字节全局占用的 ~2%。SRAM 紧张是该固件既有架构（设备身份镜像 +
描述符镜像 + USB Host Shield 缓冲区）的固有约束，早于本次改动就已存在，并非本次
引入的回归。**

已完成的无风险收缩（`TimingLock.cpp`，零行为变化，`arduino-cli compile` 验证）：
- 删除 `ratePerS` 字段（只在会话重采样时用一次算出 `refillFpPerUs`，无需常驻状态）；
- onset 延迟区间由 `uint16_t`（微秒）改存 `uint8_t`（整毫秒，原值本就是整毫秒边界）。
- 效果：2081→2077 字节（省 4 字节），已用 `arduino-cli compile --fqbn
  arduino:avr:leonardo` 重新验证通过。

**已采纳（用户明确要求后落地，2026-08）**：将 `MIRROR_REPORT_MAX` 从 256 收缩到
192（`SmartUniversalMouse.ino:19`），同时收缩 `DynamicMouseHID::descriptor[]`
与全局 `descriptorScratch[]` 两个缓冲区（各 -64 字节，共 -128 字节）。

- **安全性依据**：超限描述符不会内存越界——`DescriptorCollector::Parse()` 对
  `offset + length > outputCapacity` 做边界检查，越界只置 `overflow=true`，
  `collectReportDescriptor()` 据此返回 0，`deviceReady` 保持 false，退化为
  boot-mouse 回退路径（仍可用，只是失去完整描述符动态镜像），不是崩溃/越界风险。
- **功能取舍**：绝大多数真实鼠标的 HID Report Descriptor 在 80–150 字节区间，
  192 留有余量；极少数报文描述符超过 192 字节的复杂游戏鼠标（多 Report ID +
  宏键）会退化到 boot-mouse 回退，是已知、可接受的功能降级，不是隐藏缺陷。
- **实测结果**（`arduino-cli compile` + 实机烧录 + `diagnose_ext_humanization.py`
  回归）：SRAM 2077→**1949** 字节（76%），局部变量余量 483→**611** 字节；
  烧录到 COM110 实机后设备正常枚举，`EXT_HUMANIZATION_MODE` 协议收发验证通过。

### 9.8 抓包基线标定——现状与阻塞项

本机未安装 Wireshark / USBPcap，无法直接做 §5 设想的总线级抓包（USB 层面的
inter-packet interval 分布对拍）。可选路径：

1. **安装 USBPcap + Wireshark**：能拿到真正的总线时序（含 SOF 对齐等硬件细节），
   但需要安装内核态抓包驱动，属于环境变更，需用户明确同意后再执行。
2. **OS RawInput 时间戳近似**：写一个 Windows `WM_INPUT` 监听脚本，记录鼠标报告
   到达用户态的时间戳做统计（自相关系数、CV、分布直方图）。不是总线层原始时序
   （多一层 OS 调度抖动），但不需要安装新驱动，可用现有 Python 环境实现。

本节仅记录现状，未擅自安装抓包驱动或落地方案——需用户选择路径 1 或 2（或明确
接受路径 2 的近似误差）后再继续实施。

**路径 2 已落地（2026-08，用户选择）**：新增 `colorant/test/capture_mouse_timing_baseline.py`，
纯 `ctypes` 调 Win32 Raw Input API（`RegisterRawInputDevices` + message-only 窗口监听
`WM_INPUT`），不依赖 pywin32/内核驱动。记录报告到达 `time.perf_counter()` 时间戳，
输出：间隔均值/标准差、CV、lag-1 自相关系数、直方图；`--out` 可导出原始间隔 CSV。

- **已验证**：用 `mouse_event()` 模拟移动做端到端冒烟测试，采集到 30 个样本、
  29 个间隔，CV=0.0019、lag-1=0.113，直方图正常输出——Win32 API 调用链路（窗口
  创建/RawInput 注册/消息循环/定时退出）全部走通。
- **已知坑并修复**：64 位 Windows 上 `ctypes` 对 `user32`/`kernel32` 函数默认按
  32 位 `c_int` 处理返回值，会截断 `HWND`/`HMODULE` 指针，导致
  `RegisterRawInputDevices` 报"无效的窗口句柄"；修复方式是显式声明每个用到的
  Win32 API 的 `restype`/`argtypes`。
- **局限（用户已知悉）**：这是 OS 消息层时间戳，包含消息队列/调度抖动，不是
  总线层真实时序；用于 km.lock ON/OFF 前后对拍的近似基线，不能替代路径 1
  的总线级抓包结论。
- **未做**：真实物理鼠标 / 真实固件注入链路上的实测采样（本次只做了模拟移动的
  链路验证）；km.lock ON vs OFF 的对照统计。
