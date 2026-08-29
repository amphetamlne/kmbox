/*
 * Report Forward (km.forward) — 物理鼠标原包转发队列实现
 *
 * 设计动机与接口语义见 report_forward.h / docs/KM-LOCK.md。
 *
 * 为什么不让 Core1 直接发送：TinyUSB device API 非线程安全，
 * tud_hid_report() 只允许在跑 tud_task() 的 Core0 调用。
 * 因此物理原包先入本队列，Core0 在主循环中尽快消费——消费间隔
 * 约为主循环一圈的耗时，远小于旧架构的 1ms 定时器闸门，
 * 输出 IPI 分布由真实鼠标到达节奏主导。
 */

#include "report_forward.h"
#include <string.h>

// ARM 数据内存屏障（与 usb_hid.c 的 __dmb() 同义，内联汇编避免头文件依赖）
static inline void fwd_dmb(void) {
    __asm volatile ("dmb" ::: "memory");
}

#define REPORT_FWD_QUEUE_MASK (REPORT_FWD_QUEUE_SIZE - 1)

typedef struct {
    uint8_t data[REPORT_FWD_MAX_LEN];
    uint8_t len;
} fwd_report_entry_t;

static struct {
    fwd_report_entry_t entries[REPORT_FWD_QUEUE_SIZE];
    volatile uint8_t head;   // Core1（生产者）写入
    volatile uint8_t tail;   // Core0（消费者）写入
    volatile uint32_t overflow_count;
} g_fwd_queue;

void report_forward_init(void) {
    memset(g_fwd_queue.entries, 0, sizeof(g_fwd_queue.entries));
    g_fwd_queue.head = 0;
    g_fwd_queue.tail = 0;
    g_fwd_queue.overflow_count = 0;
}

bool report_forward_push(const uint8_t *data, uint8_t len) {
    if (data == NULL || len == 0) return false;

    uint8_t next_head = (g_fwd_queue.head + 1) & REPORT_FWD_QUEUE_MASK;
    if (next_head == g_fwd_queue.tail) {
        // 队列满：计数后返回失败，调用方回退累加路径（不丢位移）
        g_fwd_queue.overflow_count++;
        return false;
    }

    fwd_report_entry_t *e = &g_fwd_queue.entries[g_fwd_queue.head];
    if (len > REPORT_FWD_MAX_LEN) len = REPORT_FWD_MAX_LEN;
    e->len = len;
    memcpy(e->data, data, len);

    fwd_dmb();  // 数据写完再推进 head，保证消费者可见性
    g_fwd_queue.head = next_head;
    return true;
}

bool report_forward_pop(const uint8_t **data, uint8_t *len) {
    if (g_fwd_queue.tail == g_fwd_queue.head) return false;

    fwd_report_entry_t *e = &g_fwd_queue.entries[g_fwd_queue.tail];
    *data = e->data;
    *len = e->len;
    fwd_dmb();  // 先读完数据再推进 tail，避免生产者覆盖
    g_fwd_queue.tail = (g_fwd_queue.tail + 1) & REPORT_FWD_QUEUE_MASK;
    return true;
}

bool report_forward_pending(void) {
    return g_fwd_queue.tail != g_fwd_queue.head;
}

void report_forward_flush(void) {
    // 只由消费者（Core0）调用：直接对齐 tail 即清空
    g_fwd_queue.tail = g_fwd_queue.head;
}

uint8_t report_forward_depth(void) {
    return (uint8_t)((g_fwd_queue.head - g_fwd_queue.tail) & REPORT_FWD_QUEUE_MASK);
}

uint32_t report_forward_overflow_count(void) {
    return g_fwd_queue.overflow_count;
}
