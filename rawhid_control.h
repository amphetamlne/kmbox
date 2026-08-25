/*
 * RawHID Control Interface — SmartUniversalMouse protocol over vendor HID
 *
 * Exposes an extra vendor HID interface (usage page 0xFFC0 / usage 0x0C00)
 * alongside the mirrored mouse interfaces so a PC-side client (colorant)
 * can drive the firmware directly over USB without a UART bridge.
 *
 * Protocol: 8-byte legacy packets (magic 0x5A + XOR 0x3C obfuscation) and
 * A5 5A extension frames (CRC16-CCITT), compatible with SmartUniversalMouse
 * firmware v0x02.
 */

#ifndef RAWHID_CONTROL_H
#define RAWHID_CONTROL_H

#include <stdint.h>
#include <stdbool.h>

// Added to the mirrored host bcdDevice in the emulated device descriptor.
// Breaks Windows' descriptor cache keyed on VID/PID/revision, so the
// extra RawHID control interface gets a fresh enumeration instead of a
// stale cached config descriptor (e.g. from the physical mouse or an
// older firmware build with the same cloned VID/PID).
#define RAWHID_BCD_DEVICE_DELTA 0x0001

// Initialize module state (caches device UID, resets protocol state)
void rawhid_control_init(void);

// Reset protocol state (USB unmount / re-enumeration): clears handshake,
// releases any forced buttons and flushes the response queue.
void rawhid_control_reset(void);

// Handle one OUT report received on the control interface
// (called from tud_hid_set_report_cb for the RawHID instance)
void rawhid_control_handle_output(const uint8_t *data, uint16_t len);

// Periodic task: drains queued responses via tud_hid_report() and
// enforces the 30 s communication timeout. Call from the main loop.
void rawhid_control_task(void);

#endif // RAWHID_CONTROL_H
