/*
 * MuLuoxing (MILLIONXING) RP2350 USB-A 开发板头文件
 * Pico 2 兼容的 40 引脚克隆板 (50.8 x 17.8 mm), 在 Type-C 插座
 * 对端额外增加了一个 USB-A 主机插座。
 * 无公开原理图; 外设引脚映射参照 Waveshare RP2350-USB-A 参考设计
 * (boards/waveshare_rp2350_usb_a.h)。
 *
 * 关键规格:
 *   - RP2350A (QFN-56 封装, 仅 GPIO0-29) — 不是 RP2350B
 *   - 4 MB QSPI Flash (SOP8 封装, W25Q32 级别)
 *   - 12 MHz 晶振 (SDK 默认 XOSC 配置; 240 MHz 运行时
 *     CPU 时钟由项目 CMake 的 CPU_FREQ 定义设置)
 *   - USB-A 主机插座: D+ = GPIO12 (经 27R 电阻), D- = GPIO13 (经 27R 电阻),
 *     VBUS 硬连线到 VSYS (无 5V 使能 GPIO)。
 *     PIO USB 要求 DP/DM 相邻, 12/13 恰好满足; 但 GP12/13 同时
 *     引出到排针引脚 16/17, 与 USB-A 共享, 使用 USB-A 时这两根
 *     排针请勿外接其他信号
 *   - 顶部 Type-C 插座: USB 设备 / 供电 / UF2 引导加载程序
 *   - WS2812 RGB LED 接 GPIO16 (参照 Waveshare 参考设计; 若实际
 *     PCB 不同则需调整 CMake 缓存变量); GP16 同时引出到排针
 *     引脚 21, 与板载 LED 共享
 *   - BOOT / RUN 按钮各一个, 另加一个用户按钮
 *   - UART0 TX=GPIO0, RX=GPIO1 (均引出到排针)
 *   - 排针引脚: 完整 Pico 2 布局 GPIO0-22, GPIO26-28, 3V3, GND;
 *     GPIO23-25 仅供内部使用; SWD 调试焊盘位于远端
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

// -----------------------------------------------------
// 注意: 此头文件也会被汇编器包含, 因此
//       应仅包含预处理指令
// -----------------------------------------------------

#ifndef _BOARDS_MULUOXING_RP2350_USB_A_H
#define _BOARDS_MULUOXING_RP2350_USB_A_H

pico_board_cmake_set(PICO_PLATFORM, rp2350)

// 用于开发板检测
#define MULUOXING_RP2350_USB_A

// --- RP2350 型号 ---
// 该开发板使用 RP2350A (QFN-56, GPIO0-29)。
#define PICO_RP2350A 1

// --- 开发板专属引脚 ---

// USB-A 主机插座 (参照 Waveshare RP2350-USB-A 参考设计)
#define MULUOXING_RP2350_USB_A_HOST_DP_PIN      12
#define MULUOXING_RP2350_USB_A_HOST_DM_PIN      13

// WS2812 RGB LED (3V3 供电, 无独立电源引脚)
#define MULUOXING_RP2350_USB_A_WS2812_PIN       16
// 第二颗 WS2812 RGB LED (Type-C 口右侧, 经串联电阻)
#define MULUOXING_RP2350_USB_A_WS2812_PIN_2     0

// --- UART ---
#ifndef PICO_DEFAULT_UART
#define PICO_DEFAULT_UART 0
#endif
#ifndef PICO_DEFAULT_UART_TX_PIN
#define PICO_DEFAULT_UART_TX_PIN 0
#endif
#ifndef PICO_DEFAULT_UART_RX_PIN
#define PICO_DEFAULT_UART_RX_PIN 1
#endif

// --- LED ---
// 板载独立 LED (经引脚图确认), GPIO25 在 Pico 2 兼容排针上未引出。
#ifndef PICO_DEFAULT_LED_PIN
#define PICO_DEFAULT_LED_PIN 25
#endif

// --- RGB (WS2812) LED ---
#ifndef PICO_DEFAULT_WS2812_PIN
#define PICO_DEFAULT_WS2812_PIN MULUOXING_RP2350_USB_A_WS2812_PIN
#endif

#ifndef PICO_DEFAULT_WS2812_POWER_PIN
#define PICO_DEFAULT_WS2812_POWER_PIN 255
#endif

// --- PIO USB ---
#define PICO_DEFAULT_PIO_USB_DP_PIN MULUOXING_RP2350_USB_A_HOST_DP_PIN

// --- Flash ---
// 4 MB SOP8 QSPI Flash (W25Q32 级别), 兼容 W25Q080 的读取命令
#define PICO_BOOT_STAGE2_CHOOSE_W25Q080 1

#ifndef PICO_FLASH_SPI_CLKDIV
#define PICO_FLASH_SPI_CLKDIV 2
#endif

pico_board_cmake_set_default(PICO_FLASH_SIZE_BYTES, (4 * 1024 * 1024))
#ifndef PICO_FLASH_SIZE_BYTES
#define PICO_FLASH_SIZE_BYTES (4 * 1024 * 1024)
#endif

// --- A2 硅片版本支持 ---
pico_board_cmake_set_default(PICO_RP2350_A2_SUPPORTED, 1)
#ifndef PICO_RP2350_A2_SUPPORTED
#define PICO_RP2350_A2_SUPPORTED 1
#endif

#endif
