/*
 * Timing Lock (km.lock) — HID 注入时序指纹防护实现
 *
 * 三个组件（接口语义见 timing_lock.h）：
 *
 * 1. interval shaper：AR(1) 相关间隔序列
 *        dev_next = rho * dev_prev + N(0, sigma^2)
 *        interval = clamp(base + dev_next, 500, 2500)
 *    复现真实传感器"帧节律 + 晶振漂移"的短期自相关结构；逐帧独立白噪声
 *    抖动本身就是一种可辨识分布。ρ/σ 会话随机，避免参数本身成为指纹。
 *
 * 2. burst guard：
 *    - 每帧像素配额由 hid_device_task 经配额版 drain 执行（见
 *      kmbox_try_drain_mouse_16_quota），本模块只提供会话采样值；
 *    - 信用桶限制纯注入报告发射率（物理搭车帧与按钮事件不受限）。
 *
 * 3. onset/offset gate：
 *    - idle→active：首包延迟 U[onset_min, onset_max]（模拟传感器唤醒），
 *      打断"客户端发包 → 总线首包"的零延迟相关性；
 *    - active→idle：零增量停包延迟 U[offset_min, offset_max]，打断
 *      "客户端停发 → 总线立刻静默"的边缘耦合。
 *
 * 模式映射（现有三档人性化枚举，见 docs/KM-LOCK.md §4.2(d)）：
 *    OFF  —— 完全旁路（字节级行为等价于旧固件）
 *    MICRO—— 轻时序防护（输入已由客户端人性化，延迟预算收紧）
 *    FULL —— 全时序防护
 */

#include "timing_lock.h"
#include "smooth_injection.h"
#include "defines.h"          // HID_DEVICE_TASK_INTERVAL_MS
#include "pico/rand.h"        // get_rand_32() 硬件 TRNG
#include <math.h>

//--------------------------------------------------------------------+
// 常量
//--------------------------------------------------------------------+

// 与旧定时器路径一致的间隔钳位区间
#define TL_INTERVAL_MIN_US      500
#define TL_INTERVAL_MAX_US      2500
#define TL_INTERVAL_BASE_US     (HID_DEVICE_TASK_INTERVAL_MS * 1000)

// AR(1) 偏差钳位，防止极端样本把间隔钉死在边界上
#define TL_DEV_CLAMP_US         1500

// 信用桶定点（16.16）
#define TL_FP_SHIFT             16
#define TL_FP_ONE               (1 << TL_FP_SHIFT)
#define TL_CREDIT_CAP_FP        (2 * TL_FP_ONE)

// 挂起/恢复后的最大补算窗口，防止信用桶被一次长休眠灌满
#define TL_REFILL_WINDOW_MAX_US 100000

//--------------------------------------------------------------------+
// 状态
//--------------------------------------------------------------------+

typedef struct {
    bool initialized;
    humanization_mode_t mode;
    bool active;

    // (a) 间隔整形器
    float rho;             // AR(1) 自相关系数（会话随机）
    float sigma_us;        // 驱动噪声标准差
    float dev_prev_us;     // 上一帧间隔偏差

    // (b) 爆包抑制
    int16_t budget_px;     // 每帧像素抽取配额
    int32_t rate_per_s;    // 发射率上限（报告/秒）
    int32_t refill_fp_per_us;
    int32_t credits_fp;
    uint32_t last_send_us;

    // (c) 起止整形
    bool stream_active;         // 注入流进行中
    uint32_t onset_until_us;    // 首包放行时刻
    uint32_t onset_min_us;
    uint32_t onset_max_us;
    bool stop_armed;            // 停包延迟已布防
    uint32_t stop_due_us;
    uint32_t offset_min_us;
    uint32_t offset_max_us;
} timing_lock_state_t;

static timing_lock_state_t g_tl;

//--------------------------------------------------------------------+
// 会话 PRNG（xorshift32，独立于输出级与 smooth_injection 的 RNG）
//--------------------------------------------------------------------+

static uint32_t tl_rng_state = 0;

static inline uint32_t tl_rng_next(void) {
    uint32_t x = tl_rng_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    tl_rng_state = x;
    return x;
}

static inline float tl_rng_uniform01(void) {
    return (float)tl_rng_next() * (1.0f / 4294967296.0f);
}

// 4 均匀和的 CLT 高斯近似（与输出级同法），归一化到 ~N(0,1)
static inline float tl_rng_gaussian(void) {
    float sum = tl_rng_uniform01() + tl_rng_uniform01()
              + tl_rng_uniform01() + tl_rng_uniform01();
    return (sum - 2.0f) * 1.7320508f;  // 1/0.577 ≈ √3
}

static inline uint32_t tl_rng_range_u32(uint32_t lo, uint32_t hi) {
    if (hi <= lo) return lo;
    return lo + (tl_rng_next() % (hi - lo + 1));
}

//--------------------------------------------------------------------+
// 会话参数采样（模式变化时调用）
//--------------------------------------------------------------------+

static void tl_resample_session(humanization_mode_t mode) {
    switch (mode) {
        case HUMANIZATION_MICRO:
            // 轻时序防护：配额宽松、发射率上限高，延迟预算 ≤1ms 级
            g_tl.rho       = 0.20f + 0.15f * tl_rng_uniform01();
            g_tl.sigma_us  = 150.0f;
            g_tl.budget_px = (int16_t)tl_rng_range_u32(24, 40);
            g_tl.rate_per_s = 800;
            g_tl.onset_min_us  = 1000;  g_tl.onset_max_us  = 2000;
            g_tl.offset_min_us = 2000;  g_tl.offset_max_us = 4000;
            g_tl.active = true;
            break;

        case HUMANIZATION_FULL:
            // 全时序防护：配额收紧、发射率上限低，延迟预算 ≤4ms
            g_tl.rho       = 0.25f + 0.25f * tl_rng_uniform01();
            g_tl.sigma_us  = 300.0f;
            g_tl.budget_px = (int16_t)tl_rng_range_u32(12, 22);
            g_tl.rate_per_s = 500;
            g_tl.onset_min_us  = 1000;  g_tl.onset_max_us  = 3000;
            g_tl.offset_min_us = 2000;  g_tl.offset_max_us = 6000;
            g_tl.active = true;
            break;

        default:
            // OFF：完全旁路——字节级行为等价于旧固件（兼容性红线）
            g_tl.active = false;
            return;
    }

    // 参数切换后重置状态机与信用桶
    g_tl.dev_prev_us   = 0.0f;
    g_tl.credits_fp    = TL_FP_ONE;      // 允许首包立即发射
    g_tl.last_send_us  = 0;
    g_tl.stream_active = false;
    g_tl.stop_armed    = false;
    g_tl.refill_fp_per_us = (g_tl.rate_per_s * TL_FP_ONE) / 1000000;
}

//--------------------------------------------------------------------+
// 公共接口
//--------------------------------------------------------------------+

void timing_lock_init(void) {
    tl_rng_state = get_rand_32();
    if (tl_rng_state == 0) tl_rng_state = 0xA5C37E91u;  // xorshift 不能为 0
    g_tl.initialized = true;
    g_tl.mode = HUMANIZATION_MODE_COUNT;  // 强制首次 update 采样
    timing_lock_update(smooth_get_humanization_mode());
}

bool timing_lock_update(humanization_mode_t mode) {
    if (!g_tl.initialized) return false;
    if (mode != g_tl.mode) {
        g_tl.mode = mode;
        tl_resample_session(mode);
    }
    return g_tl.active;
}

bool timing_lock_active(void) {
    return g_tl.initialized && g_tl.active;
}

int32_t timing_lock_next_interval_us(void) {
    if (!g_tl.active) return TL_INTERVAL_BASE_US;

    // AR(1) 步进：保留上一帧偏差的 ρ 份额，叠加新的驱动噪声
    float dev = g_tl.rho * g_tl.dev_prev_us + tl_rng_gaussian() * g_tl.sigma_us;
    if (dev >  (float)TL_DEV_CLAMP_US) dev =  (float)TL_DEV_CLAMP_US;
    if (dev < -(float)TL_DEV_CLAMP_US) dev = -(float)TL_DEV_CLAMP_US;
    g_tl.dev_prev_us = dev;

    int32_t interval = TL_INTERVAL_BASE_US + (int32_t)dev;
    if (interval < TL_INTERVAL_MIN_US) interval = TL_INTERVAL_MIN_US;
    if (interval > TL_INTERVAL_MAX_US) interval = TL_INTERVAL_MAX_US;
    return interval;
}

int16_t timing_lock_frame_budget_px(void) {
    return g_tl.active ? g_tl.budget_px : 0;
}

bool timing_lock_allow_send(uint32_t now_us, bool inject_pending, bool buttons_changed) {
    if (!g_tl.active) return true;

    // 无待发送数据且无按钮事件：复位起始状态机（下一次突发重新布防 onset）。
    // 不触碰 stop_armed——停包可能正等待延迟放行。
    if (!inject_pending && !buttons_changed) {
        g_tl.stream_active = false;
        return true;
    }

    // 数据流恢复：取消已布防的延迟停包
    g_tl.stop_armed = false;

    // 按钮事件永远绕过时序锁（真实鼠标按钮事件不等下一帧）
    if (buttons_changed) return true;

    // onset gate：新注入流的首包延迟一个采样窗口
    if (!g_tl.stream_active) {
        g_tl.stream_active = true;
        g_tl.onset_until_us = now_us + tl_rng_range_u32(g_tl.onset_min_us, g_tl.onset_max_us);
    }
    if ((int32_t)(now_us - g_tl.onset_until_us) < 0) return false;

    // 发射率上限：信用桶。补算自上次放行以来的增量——被扣发期间
    // last_send_us 不更新，信用自然累积，放行即恢复满速一帧。
    uint32_t dt_us = (g_tl.last_send_us != 0) ? (now_us - g_tl.last_send_us) : 0;
    if (dt_us > TL_REFILL_WINDOW_MAX_US) dt_us = TL_REFILL_WINDOW_MAX_US;
    g_tl.credits_fp += (int32_t)(dt_us * (uint32_t)g_tl.refill_fp_per_us);
    if (g_tl.credits_fp > TL_CREDIT_CAP_FP) g_tl.credits_fp = TL_CREDIT_CAP_FP;

    if (g_tl.credits_fp < TL_FP_ONE) return false;   // 扣发：数据留在累加器
    g_tl.credits_fp -= TL_FP_ONE;
    g_tl.last_send_us = now_us;
    return true;
}

bool timing_lock_allow_stop(uint32_t now_us) {
    if (!g_tl.active) return true;

    // 首次观察到 active→idle 边缘：布防一个采样的 offset 延迟
    if (!g_tl.stop_armed) {
        g_tl.stop_armed = true;
        g_tl.stop_due_us = now_us + tl_rng_range_u32(g_tl.offset_min_us, g_tl.offset_max_us);
        return false;
    }
    if ((int32_t)(now_us - g_tl.stop_due_us) < 0) return false;

    // 延迟到期，放行停包并复位流状态
    g_tl.stop_armed = false;
    g_tl.stream_active = false;
    return true;
}

void timing_lock_get_stats(bool *active, int16_t *budget_px, int32_t *rate_per_s) {
    if (active)     *active     = g_tl.active;
    if (budget_px)  *budget_px  = g_tl.budget_px;
    if (rate_per_s) *rate_per_s = g_tl.rate_per_s;
}
