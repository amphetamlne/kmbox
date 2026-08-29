/*
 * Waveshare RP2350-USB-A 开发板头文件
 * 基于 Waveshare 官方 Wiki 引脚图、示例代码 (pio_usb_configuration.h)
 * 以及官方原理图网表。
 *
 * 关键规格:
 *   - RP2350A (QFN-56 封装, 仅 GPIO0-29) — 不是 RP2350B
 *   - 2 MB QSPI Flash (Winbond W25Q16JVUXIQ)
 *   - 12 MHz 晶振
 *   - 底部 USB-A 主机插座: D+ = GPIO12 (经 27R 电阻), D- = GPIO13 (经 27R 电阻)
 *     VBUS 硬连线到 VSYS (无 5V 使能 GPIO)。
 *     注意: R13 (1.5K D+ 上拉电阻) 在出厂时已焊接; Waveshare FAQ
 *     建议移除它以支持主机热插拔检测。
 *   - 顶部 Type-C 插座: USB 设备 / 供电 / UF2 引导加载程序
 *   - WS2812 RGB LED 接 GPIO16 (3V3 供电)
 *   - 无用户按钮 (仅有 BOOTSEL/RUN), 无独立 LED
 *   - UART0 TX=GPIO0, RX=GPIO1 (均引出到排针)
 *   - 排针引脚: GPIO0-10, GPIO26-29, 3V3, GND
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

// -----------------------------------------------------
// 注意: 此头文件也会被汇编器包含, 因此
//       应仅包含预处理指令
// -----------------------------------------------------

#ifndef _BOARDS_WAVESHARE_RP2350_USB_A_H
#define _BOARDS_WAVESHARE_RP2350_USB_A_H

pico_board_cmake_set(PICO_PLATFORM, rp2350)

// 用于开发板检测
#define WAVESHARE_RP2350_USB_A

// --- RP2350 型号 ---
// RP2350-USB-A 使用 RP2350A (QFN-56, GPIO0-29)。
#define PICO_RP2350A 1

// --- 开发板专属引脚 ---

// 底部 USB-A 主机插座
#define WAVESHARE_RP2350_USB_A_HOST_DP_PIN      12
#define WAVESHARE_RP2350_USB_A_HOST_DM_PIN      13

// WS2812 RGB LED (3V3 供电, 无独立电源引脚)
#define WAVESHARE_RP2350_USB_A_WS2812_PIN       16

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
// 无独立 LED; 回退到一个空闲的内部 GPIO。
#ifndef PICO_DEFAULT_LED_PIN
#define PICO_DEFAULT_LED_PIN 25
#endif

// --- RGB (WS2812) LED ---
#ifndef PICO_DEFAULT_WS2812_PIN
#define PICO_DEFAULT_WS2812_PIN WAVESHARE_RP2350_USB_A_WS2812_PIN
#endif

#ifndef PICO_DEFAULT_WS2812_POWER_PIN
#define PICO_DEFAULT_WS2812_POWER_PIN -1
#endif

// --- PIO USB ---
#define PICO_DEFAULT_PIO_USB_DP_PIN WAVESHARE_RP2350_USB_A_HOST_DP_PIN

// --- Flash ---
// Winbond W25Q16JVUXIQ (2 MB), 兼容 W25Q080 的读取命令
#define PICO_BOOT_STAGE2_CHOOSE_W25Q080 1

#ifndef PICO_FLASH_SPI_CLKDIV
#define PICO_FLASH_SPI_CLKDIV 2
#endif

pico_board_cmake_set_default(PICO_FLASH_SIZE_BYTES, (2 * 1024 * 1024))
#ifndef PICO_FLASH_SIZE_BYTES
#define PICO_FLASH_SIZE_BYTES (2 * 1024 * 1024)
#endif

// --- A2 硅片版本支持 ---
pico_board_cmake_set_default(PICO_RP2350_A2_SUPPORTED, 1)
#ifndef PICO_RP2350_A2_SUPPORTED
#define PICO_RP2350_A2_SUPPORTED 1
#endif

#endif
