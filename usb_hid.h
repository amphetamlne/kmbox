/*
* Hurricane PIOKMbox Firmware
*/

#ifndef USB_HID_H
#define USB_HID_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "tusb.h"
#include "class/hid/hid.h"
#include "class/hid/hid_device.h"
#include "class/hid/hid_host.h"
#include "kmbox_serial_handler.h"

//--------------------------------------------------------------------+
// HID REPORT DEFINITIONS
//--------------------------------------------------------------------+

// HID Report IDs for device mode
enum {
  REPORT_ID_KEYBOARD = 1,
  REPORT_ID_MOUSE,
  REPORT_ID_CONSUMER_CONTROL,
  REPORT_ID_COUNT
};

//--------------------------------------------------------------------+
// FUNCTION PROTOTYPES
//--------------------------------------------------------------------+

// Device mode functions
void hid_device_task(void);
void send_hid_report(uint8_t report_id);

// Host mode functions
void hid_host_task(void);

// Report processing functions
void process_kbd_report(hid_keyboard_report_t const *report);
void process_mouse_report(hid_mouse_report_t const *report);

// Utility functions
bool find_key_in_report(hid_keyboard_report_t const *report, uint8_t keycode);

// State management
bool usb_hid_init(void);
bool usb_host_enable_power(void);
bool get_caps_lock_state(void);
bool is_mouse_connected(void);
bool is_keyboard_connected(void);

// USB stack initialization tracking
void usb_device_mark_initialized(void);
void usb_host_mark_initialized(void);

// USB stack reset functions
bool usb_device_stack_reset(void);
bool usb_host_stack_reset(void);
bool usb_stacks_reset(void);
void usb_stack_error_check(void);

// USB Host 首次枚举自愈：开机等待窗口内若未枚举出任何 HID 设备，自动补发一次
// 等效于物理 Reset 键的芯片复位（规避 Waveshare RP2350-USB-A 板 R13 电阻缺陷）。
// 应在 core0 主循环中周期性调用（例如随 watchdog_task 一起）。
void usb_host_enum_watchdog_task(void);

// USB Host 运行期热插拔自愈：鼠标已连接期间周期性发起一次异步存活探测（控制
// 传输），真实协议层连续失败即判定物理已拔出，自动补发一次芯片复位以便重新
// 插入的设备能被正常枚举（规避 R13 缺陷导致断开事件在总线电平层面探测不到）。
// 必须在 core1 主循环（tuh_task 所在核）中周期性调用。
void usb_host_liveness_watchdog_task(void);

//--------------------------------------------------------------------+
// USB DESCRIPTORS
//--------------------------------------------------------------------+

// HID report descriptor for device mode
extern uint8_t const desc_hid_report[];

// Device descriptor
extern tusb_desc_device_t const desc_device;

// Configuration descriptor
extern uint8_t const desc_configuration[];

// String descriptors
extern char const* string_desc_arr[];

//--------------------------------------------------------------------+
// CALLBACK FUNCTION PROTOTYPES
//--------------------------------------------------------------------+

// Device callbacks
void tud_mount_cb(void);
void tud_umount_cb(void);
void tud_suspend_cb(bool remote_wakeup_en);
void tud_resume_cb(void);

// HID device callbacks
uint16_t tud_hid_get_report_cb(uint8_t instance, uint8_t report_id, hid_report_type_t report_type, uint8_t* buffer, uint16_t reqlen);
void tud_hid_set_report_cb(uint8_t instance, uint8_t report_id, hid_report_type_t report_type, uint8_t const* buffer, uint16_t bufsize);
void tud_hid_report_complete_cb(uint8_t instance, uint8_t const* report, uint16_t len);

// HID host callbacks
extern uint16_t attached_vid;
extern uint16_t attached_pid;

// Function to get the VID of the attached device
uint16_t get_attached_vid(void);

// Function to get the PID of the attached device
uint16_t get_attached_pid(void);

// Function to set the VID and PID of the attached device
void set_attached_device_vid_pid(uint16_t vid, uint16_t pid);

// Functions to get attached device string descriptors
const char* get_attached_manufacturer(void);
const char* get_attached_product(void);

// Function to get dynamic serial string
const char* get_dynamic_serial_string(void);

// Function to force USB re-enumeration
void force_usb_reenumeration(void);

//--------------------------------------------------------------------+
// RawHID CONTROL INTERFACE ACCESSORS (rawhid_control.c)
//--------------------------------------------------------------------+

// Device-side HID instance index of the vendor RawHID control interface
// (appended after the mirrored interfaces in the configuration descriptor)
uint8_t usbhid_get_rawhid_instance(void);

// Cloned host mouse report descriptor (NULL via *len=0 when unavailable)
const uint8_t *usbhid_get_mouse_desc(size_t *len);

// Descriptor generation counter — increments on every output descriptor
// rebuild (mouse attach/detach), used by the control protocol to detect
// layout changes
uint16_t usbhid_get_mouse_desc_generation(void);

// TinyUSB Host callbacks
void tuh_hid_mount_cb(uint8_t dev_addr, uint8_t instance, uint8_t const* desc_report, uint16_t desc_len);
void tuh_hid_umount_cb(uint8_t dev_addr, uint8_t instance);
void tuh_hid_report_received_cb(uint8_t dev_addr, uint8_t instance, uint8_t const* report, uint16_t len);

// Descriptor callbacks
uint8_t const * tud_descriptor_device_cb(void);
uint8_t const * tud_hid_descriptor_report_cb(uint8_t instance);
uint8_t const * tud_descriptor_configuration_cb(uint8_t index);
uint16_t const* tud_descriptor_string_cb(uint8_t index, uint16_t langid);

#endif // USB_HID_H