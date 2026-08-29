/*
 * Report Forward (km.forward) — 物理鼠标原包转发队列
 *
 * km.forward 是 km.lock 的姊妹层（见 docs/KM-LOCK.md §7 后续落地说明）：
 * 物理鼠标报告不再被拆解进累加器后由 Core0 按自制时钟重发，而是整包进入
 * 本队列，由 Core0 尽快发出——输出时序尽可能贴近真实传感器节律，注入
 * 修正量在发送前叠加进 X/Y 字段（搭车合并）。
 *
 * 并发模型：Core1（tuh_hid_report_received_cb 路径）单生产者，
 * Core0（hid_device_task）单消费者。与 vendor_fwd_queue 同构的
 * SPSC 环形队列，volatile head/tail + __dmb()，无需互斥锁。
 */

#ifndef REPORT_FORWARD_H
#define REPORT_FORWARD_H

#include <stdint.h>
#include <stdbool.h>

// 与 host 侧最大鼠标报告尺寸对齐（vendor 通道同为 64 字节）
#define REPORT_FWD_MAX_LEN 64
// 32 槽：1kHz 鼠标约 32ms 缓冲；队列满时生产者回退累加路径（不丢位移）
#define REPORT_FWD_QUEUE_SIZE 32

/**
 * 初始化队列（清零）。在 usb_device 初始化时调用一次。
 */
void report_forward_init(void);

/**
 * 生产者（Core1）：入队一个原包。
 * @return false = 队列满——调用方必须回退累加路径以保住位移数据
 */
bool report_forward_push(const uint8_t *data, uint8_t len);

/**
 * 消费者（Core0）：取队首条目。返回的指针指向队列内部存储，
 * 有效期至下一次 report_forward_pop/flush（单消费者，安全）。
 * @return false = 队列空
 */
bool report_forward_pop(const uint8_t **data, uint8_t *len);

/**
 * 队列是否有待转发条目。
 */
bool report_forward_pending(void);

/**
 * 清空队列（模式切换/断连时丢弃陈旧原包）。
 */
void report_forward_flush(void);

/**
 * 当前队列深度（观测用，KMBOX_INFO）。
 */
uint8_t report_forward_depth(void);

/**
 * 累计队列满次数（生产者回退累加路径的次数，观测用）。
 */
uint32_t report_forward_overflow_count(void);

#endif // REPORT_FORWARD_H
