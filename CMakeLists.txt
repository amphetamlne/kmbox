# Cmake Pico 项目自动生成文件

cmake_minimum_required(VERSION 3.13)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# 从安装位置初始化 pico_sdk
#（注意：SDK 路径可来自环境变量、CMake 缓存等）

# == 请勿修改以下行，否则 Raspberry Pi Pico VS Code 扩展将无法工作 ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()
set(sdkVersion 2.2.0)
set(toolchainVersion 14_2_Rel1)
set(picotoolVersion 2.2.0)
set(PICO_SDK_PATH $ENV{HOME}/.pico-sdk/sdk/2.2.0-fresh)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================
# 开发板选择：waveshare_rp2350_usb_a / muluoxing_rp2350_usb_a / adafruit_metro_rp2350 / pico2（仅限 RP2350）
set(PICO_BOARD waveshare_rp2350_usb_a CACHE STRING "Board type")

# 告诉 SDK 自定义板级头文件所在目录（如 adafruit_metro_rp2350.h）
set(PICO_BOARD_HEADER_DIRS ${CMAKE_CURRENT_LIST_DIR}/boards)

# 根据开发板类型设置对应的引脚配置
# 状态 LED 是否随 USB 设备挂载状态闪烁（默认启用），各板可在下方覆盖
set(STATUS_LED_BLINK 1 CACHE STRING "Status LED blinks with USB mount state (1=blink, 0=steady on)")

# 主 WS2812 (GPIO16) 全局亮度上限 (0-255)，各板 LED/漫射罩差异较大，可在下方覆盖
set(NEOPIXEL_BRIGHTNESS 20 CACHE STRING "Global NeoPixel brightness cap (0-255)")

if(PICO_BOARD STREQUAL "adafruit_metro_rp2350")
    set(USB_HOST_DP_PIN 32 CACHE STRING "USB Host D+ pin")
    set(USB_HOST_DM_PIN 33 CACHE STRING "USB Host D- pin")
    set(USB_HOST_5V_PIN 29 CACHE STRING "USB Host 5V power pin")
    set(LED_PIN 23 CACHE STRING "Status LED pin")
    set(NEOPIXEL_PIN 25 CACHE STRING "NeoPixel data pin")
    set(NEOPIXEL_POWER_PIN 255 CACHE STRING "NeoPixel power pin (255=not used)")
    message(STATUS "Configuring for Adafruit Metro RP2350 - USB Host on GPIO32/33")
elseif(PICO_BOARD STREQUAL "waveshare_rp2350_usb_a")
    # Waveshare RP2350-USB-A（RP2350A，仅 GPIO0-29）：
    # 底部 USB-A 接口 D+=GPIO12 / D-=GPIO13，VBUS 硬连线到 VSYS
    #（无 5V 使能 GPIO -> 使用一个无害的空闲内部 GPIO），
    # WS2812 接 GPIO16，板载无独立 LED -> 使用空闲内部 GPIO。
    set(USB_HOST_DP_PIN 12 CACHE STRING "USB Host D+ pin")
    set(USB_HOST_DM_PIN 13 CACHE STRING "USB Host D- pin")
    set(USB_HOST_5V_PIN 15 CACHE STRING "USB Host 5V power pin (dummy, VBUS always on)")
    set(LED_PIN 17 CACHE STRING "Status LED pin (dummy, no LED on board)")
    set(NEOPIXEL_PIN 16 CACHE STRING "NeoPixel data pin")
    set(NEOPIXEL_POWER_PIN 255 CACHE STRING "NeoPixel power pin (255=not used)")
    set(NEOPIXEL_BRIGHTNESS 12 CACHE STRING "Global NeoPixel brightness cap (0-255)" FORCE)
    message(STATUS "Configuring for Waveshare RP2350-USB-A - USB Host on GPIO12/13")
elseif(PICO_BOARD STREQUAL "muluoxing_rp2350_usb_a")
    # 多乐星（MILLIONXING）RP2350 USB-A（Pico 2 兼容引脚，RP2350A，4MB Flash）：
    # USB-A 接口 D+=GPIO12 / D-=GPIO13（参照 Waveshare RP2350-USB-A 参考设计），
    # VBUS 硬连线到 VSYS（无 5V 使能 GPIO -> 使用仅内部可访问的 GPIO23），
    # WS2812 接 GPIO16
    #（GPIO23 在 Pico 2 兼容排针上未引出）。
    # 已移除板载第二颗 LED（GPIO25，PIO1 驱动 WS2812）：与 LED_PIN 复用同一引脚，
    # 怀疑其信号干扰经板级布线耦合到 USB Host D+/D-，导致该板独有的热插拔卡死问题。
    set(USB_HOST_DP_PIN 12 CACHE STRING "USB Host D+ pin")
    set(USB_HOST_DM_PIN 13 CACHE STRING "USB Host D- pin")
    set(USB_HOST_5V_PIN 23 CACHE STRING "USB Host 5V power pin (internal-only GPIO23, VBUS always on)")
    set(LED_PIN 25 CACHE STRING "Status LED pin (on-board LED)")
    set(NEOPIXEL_PIN 16 CACHE STRING "NeoPixel data pin")
    set(NEOPIXEL_POWER_PIN 255 CACHE STRING "NeoPixel power pin (255=not used)")
    set(STATUS_LED_BLINK 0 CACHE STRING "Status LED blinks with USB mount state (1=blink, 0=steady on)" FORCE)
    set(NEOPIXEL_BRIGHTNESS 40 CACHE STRING "Global NeoPixel brightness cap (0-255)" FORCE)
    message(STATUS "Configuring for MuLuoxing RP2350-USB-A - USB Host on GPIO12/13")
else()
    # 默认配置：Pico/Pico2，PIO USB 使用常见 GPIO16/17
    set(USB_HOST_DP_PIN 16 CACHE STRING "USB Host D+ pin")
    set(USB_HOST_DM_PIN 17 CACHE STRING "USB Host D- pin")
    set(USB_HOST_5V_PIN 18 CACHE STRING "USB Host 5V power pin")
    set(LED_PIN 25 CACHE STRING "Status LED pin")
    set(NEOPIXEL_PIN 21 CACHE STRING "NeoPixel data pin")
    set(NEOPIXEL_POWER_PIN 20 CACHE STRING "NeoPixel power pin")
    message(STATUS "Configuring for ${PICO_BOARD} - USB Host on GPIO16/17")
endif()

# UART 实例：0 = uart0（GPIO 0/1），1 = uart1（GPIO 8/9）
set(KMBOX_UART_INSTANCE 0 CACHE STRING "UART instance for bridge communication (0 or 1)")

# 引入 Raspberry Pi Pico SDK（必须在 project() 之前）
include(pico_sdk_import.cmake)

project(PIOKMbox C CXX ASM)

# 初始化 Raspberry Pi Pico SDK
pico_sdk_init()

# 添加可执行目标，默认目标名为项目名，版本 0.1

add_executable(PIOKMbox
    PIOKMbox.c
    led_control.c
    usb_hid.c
    rawhid_control.c
    watchdog.c
    state_management.c
    kmbox_serial_handler.c
    smooth_injection.c
    timing_lock.c
    report_forward.c
    humanization_fpu.c
    dcp_helpers.S
    xbox_host.c
    xbox_device.c
)

# 生成 PIO 头文件到源码目录，供 RP2040 数据手册中的代码引用
pico_generate_pio_header(PIOKMbox ${CMAKE_CURRENT_LIST_DIR}/ws2812.pio OUTPUT_DIR ${CMAKE_CURRENT_LIST_DIR})

pico_set_program_name(PIOKMbox "PIOKMbox")
pico_set_program_version(PIOKMbox "0.1")

# 启用/禁用 UART/USB 调试输出
# UART0 用于 KMBox 串口输入（通过 RP2350 USB Bridge）
# USB CDC 已禁用，避免干扰 HID 枚举
# 调试信息可通过 KMBox 接口转发输出
pico_enable_stdio_uart(PIOKMbox 1)
pico_enable_stdio_usb(PIOKMbox 0)

# 240MHz 主频下的性能优化编译选项
# -O3：激进的内联与向量化优化
# -ffast-math：启用 Cortex-M33 FPU 的 VFMA（乘加融合）指令
# -funroll-loops：展开紧凑内层循环（有助于 DMA/UART 数据处理）
# -ffunction-sections -fdata-sections：配合 --gc-sections 实现死代码消除
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -ffast-math -funroll-loops -ffunction-sections -fdata-sections")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -ffast-math -funroll-loops -ffunction-sections -fdata-sections")
target_link_options(PIOKMbox PRIVATE -Wl,--gc-sections)

# 链接标准库
target_link_libraries(PIOKMbox
        pico_stdlib
        tinyusb_device
        tinyusb_host
        tinyusb_board
        hardware_pio
        hardware_dma
        hardware_watchdog
        hardware_uart
        hardware_spi
        hardware_irq
        hardware_adc
        pico_unique_id
        pico_multicore
        hardware_dcp
        pico_flash
        pico_rand
        pico_time
        m)

# 添加 PIO USB 库
add_subdirectory(lib/Pico-PIO-USB)

# 添加 KMBox 命令库
add_subdirectory(lib/kmbox-commands)

# 共享库
add_subdirectory(lib/hid-defs)
add_subdirectory(lib/fast-protocol)
add_subdirectory(lib/wire-protocol)
add_subdirectory(lib/peri-clock)
add_subdirectory(lib/dma-uart)
add_subdirectory(lib/led-utils)

# PIO USB 库支持（已启用）
message(STATUS "PIO USB library support enabled")
# 添加 TinyUSB 编译定义及引脚配置
target_compile_definitions(PIOKMbox PRIVATE
        CFG_TUSB_CONFIG_FILE="tusb_config.h"
        BOARD_TUH_RHPORT=1
        BOARD_TUD_RHPORT=0
        PIO_USB_USE_TINYUSB
        BUILD_CONFIG=BUILD_CONFIG_DEVELOPMENT
        PIO_USB_AVAILABLE=1
        CFG_TUH_RPI_PIO_USB=1
        CPU_FREQ=240000
        KMBOX_UART_INSTANCE=${KMBOX_UART_INSTANCE}
        PIN_USB_HOST_DP=${USB_HOST_DP_PIN}
        PIN_USB_HOST_DM=${USB_HOST_DM_PIN}
        PIN_USB_5V=${USB_HOST_5V_PIN}
        PIN_LED=${LED_PIN}
        STATUS_LED_BLINK_ENABLED=${STATUS_LED_BLINK}
        PIN_NEOPIXEL=${NEOPIXEL_PIN}
        NEOPIXEL_GLOBAL_BRIGHTNESS_CAP=${NEOPIXEL_BRIGHTNESS}
        NEOPIXEL_POWER=${NEOPIXEL_POWER_PIN}
        ENABLE_XBOX_PASSTHROUGH=1
)

# 链接 PIO USB 库
target_link_libraries(PIOKMbox pico_pio_usb)

# 链接 KMBox 命令库
target_link_libraries(PIOKMbox kmbox_commands)

# 链接共享库
target_link_libraries(PIOKMbox hid_defs fast_protocol wire_protocol peri_clock dma_uart led_utils)

# 直接添加 PIO USB HCD 实现源码
target_sources(PIOKMbox PRIVATE
    ${PICO_TINYUSB_PATH}/src/portable/raspberrypi/pio_usb/dcd_pio_usb.c
    ${PICO_TINYUSB_PATH}/src/portable/raspberrypi/pio_usb/hcd_pio_usb.c
 )

# 添加标准头文件搜索路径
target_include_directories(PIOKMbox PRIVATE
        ${CMAKE_CURRENT_LIST_DIR}
        ${CMAKE_CURRENT_LIST_DIR}/src
)

pico_add_extra_outputs(PIOKMbox)
