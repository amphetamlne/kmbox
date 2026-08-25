/*
 * Board header for Waveshare RP2350-USB-A
 * Based on official Waveshare wiki pinout, demo code (pio_usb_configuration.h)
 * and the official schematic netlist.
 *
 * Key specs:
 *   - RP2350A (QFN-56, GPIO0-29 only) — NOT RP2350B
 *   - 2 MB QSPI flash (Winbond W25Q16JVUXIQ)
 *   - 12 MHz crystal
 *   - Bottom USB-A host socket: D+ = GPIO12 (via 27R), D- = GPIO13 (via 27R)
 *     VBUS is hardwired to VSYS (no 5V enable GPIO).
 *     NOTE: R13 (1.5K D+ pull-up) is fitted at factory; the Waveshare FAQ
 *     says to remove it for host hot-plug detection.
 *   - Top Type-C socket: USB device / power / UF2 bootloader
 *   - WS2812 RGB LED on GPIO16 (3V3 powered)
 *   - No user button (BOOTSEL/RUN only), no discrete LED
 *   - UART0 TX=GPIO0, RX=GPIO1 (both on header)
 *   - Header pins: GPIO0-10, GPIO26-29, 3V3, GND
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

// -----------------------------------------------------
// NOTE: THIS HEADER IS ALSO INCLUDED BY ASSEMBLER SO
//       SHOULD ONLY CONSIST OF PREPROCESSOR DIRECTIVES
// -----------------------------------------------------

#ifndef _BOARDS_WAVESHARE_RP2350_USB_A_H
#define _BOARDS_WAVESHARE_RP2350_USB_A_H

pico_board_cmake_set(PICO_PLATFORM, rp2350)

// For board detection
#define WAVESHARE_RP2350_USB_A

// --- RP2350 VARIANT ---
// RP2350-USB-A uses the RP2350A (QFN-56, GPIO0-29).
#define PICO_RP2350A 1

// --- BOARD-SPECIFIC PINS ---

// Bottom USB-A host socket
#define WAVESHARE_RP2350_USB_A_HOST_DP_PIN      12
#define WAVESHARE_RP2350_USB_A_HOST_DM_PIN      13

// WS2812 RGB LED (3V3 powered, no separate power pin)
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
// No discrete LED; fall back to a free internal GPIO.
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

// --- FLASH ---
// Winbond W25Q16JVUXIQ (2 MB), W25Q080-compatible read commands
#define PICO_BOOT_STAGE2_CHOOSE_W25Q080 1

#ifndef PICO_FLASH_SPI_CLKDIV
#define PICO_FLASH_SPI_CLKDIV 2
#endif

pico_board_cmake_set_default(PICO_FLASH_SIZE_BYTES, (2 * 1024 * 1024))
#ifndef PICO_FLASH_SIZE_BYTES
#define PICO_FLASH_SIZE_BYTES (2 * 1024 * 1024)
#endif

// --- A2 SILICON SUPPORT ---
pico_board_cmake_set_default(PICO_RP2350_A2_SUPPORTED, 1)
#ifndef PICO_RP2350_A2_SUPPORTED
#define PICO_RP2350_A2_SUPPORTED 1
#endif

#endif
