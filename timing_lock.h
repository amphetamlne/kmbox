/*
 * Timing Lock (km.lock) — HID 注入时序指纹防护
 *
 * 挂载在 hid_device_task 的 drain→send 边界，对三路累加信号统一生效：
 *   (a) interval shaper  —— AR(1) 相关间隔序列，替换逐帧独立高斯抖动
 *   (b) burst guard      —— 配额抽取预算 + 信用桶发射率上限
 *   (c) onset/offset gate—— 首包延迟（模拟传感器唤醒）+ 停包延迟
 *
 * 命名对应已有命令族：km.lock_mx/my（轴锁）→ km.lock（时序锁）。
 * 设计详见 docs/KM-LOCK.md。
 *
 * 兼容性红线：HUMANIZATION_OFF 档完全旁路，字节级行为等价于旧固件。
 * 按钮事件与物理鼠标搭车帧永远绕过时序锁（真实鼠标语义）。
 *
 * 并发模型：仅 Core0 的 hid_device_task 读写本模块状态，无需加锁。
 */

#ifndef TIMING_LOCK_H
#define TIMING_LOCK_H

#include <stdint.h>
#include <stdbool.h>
#include "smooth_injection.h"

/**
 * 初始化时序锁（用硬件 TRNG 播种会话 PRNG）。
 * 在 usb_device 初始化时调用一次。
 */
void timing_lock_init(void);

/**
 * 同步人性化模式；模式变化时重采样全部会话参数（ρ/σ/配额/起止区间）。
 * @return 时序锁是否处于激活状态（mode != HUMANIZATION_OFF）
 */
bool timing_lock_update(humanization_mode_t mode);

/**
 * 时序锁当前是否激活（供观测路径使用）。
 */
bool timing_lock_active(void);

/**
 * 间隔整形器：返回下一次报告间隔（µs，钳位 [500, 2500]）。
 * 每次调用推进一次 AR(1) 状态。仅在激活态调用。
 */
int32_t timing_lock_next_interval_us(void);

/**
 * 纯注入帧发送门控：起始延迟（onset）+ 发射率上限（信用桶）。
 * 在抽取累加器之前调用；返回 false 表示本帧扣发（数据留在累加器）。
 *
 * @param now_us          当前 time_us_32()
 * @param inject_pending  是否有注入数据待发送
 * @param buttons_changed 按钮状态变化——永远旁路时序锁
 * @return true = 允许发送
 */
bool timing_lock_allow_send(uint32_t now_us, bool inject_pending, bool buttons_changed);

/**
 * active→idle 停包门控：把零增量停包延迟一个采样的 offset 时间再放行，
 * 打断"客户端停发 → 总线立刻静默"的边缘耦合。仅在激活态调用。
 *
 * @return true = 停包可以发出
 */
bool timing_lock_allow_stop(uint32_t now_us);

/**
 * 当前每帧像素抽取配额（≤0 = 不限量）。供配额版 drain 使用。
 */
int16_t timing_lock_frame_budget_px(void);

/**
 * 观测接口（KMBOX_INFO 用）。任一输出指针可为 NULL。
 */
void timing_lock_get_stats(bool *active, int16_t *budget_px, int32_t *rate_per_s);

#endif // TIMING_LOCK_H
