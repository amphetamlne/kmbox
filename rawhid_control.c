/*
 * RawHID Control Interface — SmartUniversalMouse protocol implementation
 *
 * Wire format (identical to SmartUniversalMouse.ino / colorant client):
 *
 * Legacy 8-byte packet:
 *   [0]=0x5A magic, [1]=cmd, [2..6]=payload, [7]=checksum
 *   checksum = XOR(bytes 0..6) computed BEFORE obfuscation,
 *   then bytes [1..6] are XORed with 0x3C.
 *
 * Extension frame (max 64 bytes on the wire):
 *   A5 5A ver(0x01) type seq_lo seq_hi len payload... crc_lo crc_hi
 *   CRC16-CCITT (init 0xFFFF, poly 0x1021, MSB-first) over header+payload,
 *   appended little-endian. Responses set bit 0x80 on the frame type.
 *
 * All responses are pushed as full 64-byte interrupt IN reports (zero
 * padded); the client reads 64-byte reports without a report-ID prefix.
 */

#include <string.h>

#include "tusb.h"
#include "pico/stdlib.h"
#include "hardware/flash.h"   // flash_get_unique_id()

#include "rawhid_control.h"
#include "usb_hid.h"
#include "kmbox_commands.h"

//--------------------------------------------------------------------+
// Protocol constants (SmartUniversalMouse v0x02)
//--------------------------------------------------------------------+

#define RAWHID_PROTOCOL_VERSION   0x02

#define RAWHID_MAGIC              0x5A
#define RAWHID_XOR_KEY            0x3C
#define RAWHID_PACKET_SIZE        8

#define RAWHID_CMD_HANDSHAKE      0x01
#define RAWHID_CMD_ACK            0x02
#define RAWHID_CMD_MOVE           0x03
#define RAWHID_CMD_CLICK          0x04
#define RAWHID_CMD_PRESS          0x05
#define RAWHID_CMD_RELEASE        0x06
#define RAWHID_CMD_HEARTBEAT      0x07
#define RAWHID_CMD_GET_DEVICE_ID  0x08
#define RAWHID_CMD_PING           0xAB

#define RAWHID_EXT_MAGIC_0        0xA5
#define RAWHID_EXT_MAGIC_1        0x5A
#define RAWHID_EXT_VERSION        0x01
#define RAWHID_EXT_PAYLOAD_MAX    48

#define RAWHID_EXT_DESCRIPTOR_META   0x10
#define RAWHID_EXT_DESCRIPTOR_CHUNK  0x11
#define RAWHID_EXT_LAYOUT_BEGIN      0x12
#define RAWHID_EXT_LAYOUT_FIELD      0x13
#define RAWHID_EXT_LAYOUT_COMMIT     0x14
#define RAWHID_EXT_INJECTION_STATUS  0x15
#define RAWHID_EXT_RESPONSE          0x80

// Heartbeat status bits
#define RAWHID_STATUS_READY           0x01
#define RAWHID_STATUS_MOUSE_CONNECTED 0x02
#define RAWHID_STATUS_HANDSHAKED      0x04
#define RAWHID_STATUS_REATTACHING     0x08

// Client stops sending after 30 s of silence on our side; mirror that:
// drop the handshake if nothing arrives for 30 s.
#define RAWHID_CONNECTION_TIMEOUT_MS  30000u

#define RAWHID_FRAME_SIZE           64
#define RAWHID_RESP_QUEUE_SIZE      8   // power of two
#define RAWHID_RESP_QUEUE_MASK      (RAWHID_RESP_QUEUE_SIZE - 1)

//--------------------------------------------------------------------+
// Module state
//--------------------------------------------------------------------+

typedef struct {
    bool     handshaked;
    uint32_t last_rx_ms;

    // Absolute software button mask last applied via MOVE packets
    uint8_t  sw_buttons_mask;

    // Layout negotiation (client-driven; our injection engine is agnostic)
    uint16_t layout_generation;
    uint8_t  layout_wire_len;
    bool     layout_committed;

    uint8_t  device_uid[8];

    // Response queue (64-byte frames)
    uint8_t  resp_queue[RAWHID_RESP_QUEUE_SIZE][RAWHID_FRAME_SIZE];
    volatile uint8_t resp_head;
    volatile uint8_t resp_tail;
} rawhid_state_t;

static rawhid_state_t rawhid;

//--------------------------------------------------------------------+
// Low-level helpers
//--------------------------------------------------------------------+

static uint16_t crc16_ccitt(const uint8_t *data, uint16_t len)
{
    uint16_t crc = 0xFFFF;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int b = 0; b < 8; b++) {
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021)
                                 : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

// Enqueue a raw 64-byte frame; copies `len` bytes and zero-pads the rest.
static void resp_enqueue(const uint8_t *frame, uint16_t len)
{
    uint8_t next_head = (rawhid.resp_head + 1) & RAWHID_RESP_QUEUE_MASK;
    if (next_head == rawhid.resp_tail) return;  // full — drop

    uint8_t *slot = rawhid.resp_queue[rawhid.resp_head];
    uint16_t copy_len = (len > RAWHID_FRAME_SIZE) ? RAWHID_FRAME_SIZE : len;
    memcpy(slot, frame, copy_len);
    if (copy_len < RAWHID_FRAME_SIZE) {
        memset(slot + copy_len, 0, RAWHID_FRAME_SIZE - copy_len);
    }
    rawhid.resp_head = next_head;
}

//--------------------------------------------------------------------+
// Legacy 8-byte packets
//--------------------------------------------------------------------+

// Build and enqueue an obfuscated legacy packet. payload may be NULL.
static void send_legacy(uint8_t cmd, const uint8_t payload[5])
{
    uint8_t pkt[RAWHID_PACKET_SIZE];
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = RAWHID_MAGIC;
    pkt[1] = cmd;
    if (payload != NULL) {
        memcpy(&pkt[2], payload, 5);
    }

    uint8_t checksum = 0;
    for (int i = 0; i < RAWHID_PACKET_SIZE - 1; i++) checksum ^= pkt[i];
    pkt[7] = checksum;

    // Obfuscate bytes [1..6] (checksum was computed pre-obfuscation)
    for (int i = 1; i < RAWHID_PACKET_SIZE - 1; i++) pkt[i] ^= RAWHID_XOR_KEY;

    resp_enqueue(pkt, sizeof(pkt));
}

// Decode an incoming legacy packet in place; returns cmd or -1 on error.
// On success payload[0..4] holds the deobfuscated payload bytes.
static int legacy_decode(const uint8_t *data, uint16_t len, uint8_t payload[5])
{
    if (len < RAWHID_PACKET_SIZE || data[0] != RAWHID_MAGIC) return -1;

    uint8_t pkt[RAWHID_PACKET_SIZE];
    memcpy(pkt, data, RAWHID_PACKET_SIZE);
    for (int i = 1; i < RAWHID_PACKET_SIZE - 1; i++) pkt[i] ^= RAWHID_XOR_KEY;

    uint8_t checksum = 0;
    for (int i = 0; i < RAWHID_PACKET_SIZE - 1; i++) checksum ^= pkt[i];
    if (checksum != pkt[7]) return -1;

    memcpy(payload, &pkt[2], 5);
    return pkt[1];
}

// Map a HID button bit (0x01 left ... 0x10 side2) to kmbox button index
static kmbox_button_t bit_to_button(uint8_t bit)
{
    switch (bit) {
        case 0x01: return KMBOX_BUTTON_LEFT;
        case 0x02: return KMBOX_BUTTON_RIGHT;
        case 0x04: return KMBOX_BUTTON_MIDDLE;
        case 0x08: return KMBOX_BUTTON_SIDE1;
        case 0x10: return KMBOX_BUTTON_SIDE2;
        default:   return KMBOX_BUTTON_COUNT;
    }
}

// Release every button we might be forcing
static void release_all_forced_buttons(uint32_t now)
{
    for (uint8_t b = 0; b < KMBOX_BUTTON_COUNT; b++) {
        kmbox_force_button((kmbox_button_t)b, false, now);
    }
}

// Apply an absolute button mask (MOVE packets carry the full mask)
static void apply_button_mask(uint8_t new_mask, uint32_t now)
{
    uint8_t diff = new_mask ^ rawhid.sw_buttons_mask;
    if (diff == 0) return;

    for (uint8_t bit = 0x01; bit <= 0x10; bit <<= 1) {
        if (!(diff & bit)) continue;
        kmbox_button_t btn = bit_to_button(bit);
        if (btn >= KMBOX_BUTTON_COUNT) continue;
        kmbox_force_button(btn, (new_mask & bit) != 0, now);
    }
    rawhid.sw_buttons_mask = new_mask;
}

// Press/release/click every button set in the mask
static void apply_button_action(uint8_t cmd, uint8_t mask, uint32_t now)
{
    if (mask == 0) {
        if (cmd == RAWHID_CMD_RELEASE) release_all_forced_buttons(now);
        return;
    }
    for (uint8_t bit = 0x01; bit <= 0x10; bit <<= 1) {
        if (!(mask & bit)) continue;
        kmbox_button_t btn = bit_to_button(bit);
        if (btn >= KMBOX_BUTTON_COUNT) continue;
        if (cmd == RAWHID_CMD_CLICK) {
            kmbox_start_button_click(btn, now);
        } else {
            kmbox_force_button(btn, cmd == RAWHID_CMD_PRESS, now);
            // Keep the tracked mask consistent for subsequent MOVE packets
            if (cmd == RAWHID_CMD_PRESS) rawhid.sw_buttons_mask |= bit;
            else                         rawhid.sw_buttons_mask &= (uint8_t)~bit;
        }
    }
}

static uint8_t heartbeat_status(void)
{
    uint8_t status = RAWHID_STATUS_READY;
    if (is_mouse_connected())    status |= RAWHID_STATUS_MOUSE_CONNECTED;
    if (rawhid.handshaked)       status |= RAWHID_STATUS_HANDSHAKED;
    return status;
}

// PONG payload: status, version, generation(LE), reserved(=0), reserved(=0)
static void send_heartbeat(void)
{
    uint16_t gen = usbhid_get_mouse_desc_generation();
    uint8_t payload[5] = {
        heartbeat_status(),
        RAWHID_PROTOCOL_VERSION,
        (uint8_t)(gen & 0xFF),
        (uint8_t)((gen >> 8) & 0xFF),
        0   // client strictly requires this byte to be 0
    };
    send_legacy(RAWHID_CMD_HEARTBEAT, payload);
}

static void send_device_uid(void)
{
    // Two-part response: part 1 = uid[0..3], part 2 = uid[4..7]
    uint8_t payload[5];
    memcpy(payload, &rawhid.device_uid[0], 4);
    payload[4] = 0x01;
    send_legacy(RAWHID_CMD_GET_DEVICE_ID, payload);

    memcpy(payload, &rawhid.device_uid[4], 4);
    payload[4] = 0x02;
    send_legacy(RAWHID_CMD_GET_DEVICE_ID, payload);
}

static void handle_legacy(const uint8_t *data, uint16_t len)
{
    uint8_t payload[5];
    int cmd = legacy_decode(data, len, payload);
    if (cmd < 0) return;

    uint32_t now = to_ms_since_boot(get_absolute_time());
    rawhid.last_rx_ms = now;

    switch ((uint8_t)cmd) {
        case RAWHID_CMD_HANDSHAKE: {
            // payload[0] carries the client protocol version
            uint8_t ack[5] = { 0 };
            ack[0] = RAWHID_PROTOCOL_VERSION;  // let the client verify it
            send_legacy(RAWHID_CMD_ACK, ack);
            rawhid.handshaked = (payload[0] == RAWHID_PROTOCOL_VERSION);
            break;
        }

        case RAWHID_CMD_PING:
        case RAWHID_CMD_HEARTBEAT:
            send_heartbeat();
            break;

        case RAWHID_CMD_GET_DEVICE_ID:
            send_device_uid();
            break;

        case RAWHID_CMD_MOVE: {
            if (!rawhid.handshaked) break;
            int16_t x = (int16_t)(uint16_t)(payload[0] | (payload[1] << 8));
            int16_t y = (int16_t)(uint16_t)(payload[2] | (payload[3] << 8));
            apply_button_mask(payload[4], now);
            if (x != 0 || y != 0) {
                // Client already splits deltas to fit the logical range;
                // feed the fast accumulator directly for minimum latency.
                kmbox_add_mouse_movement(x, y);
            }
            break;
        }

        case RAWHID_CMD_CLICK:
        case RAWHID_CMD_PRESS:
        case RAWHID_CMD_RELEASE:
            if (!rawhid.handshaked) break;
            apply_button_action((uint8_t)cmd, payload[4], now);
            break;

        default:
            break;
    }
}

//--------------------------------------------------------------------+
// Extension frames (descriptor exposure + layout negotiation)
//--------------------------------------------------------------------+

// Enqueue an extension response frame (type | 0x80, same sequence)
static void send_ext_response(uint8_t type, uint16_t seq,
                              const uint8_t *payload, uint8_t plen)
{
    if (plen > RAWHID_EXT_PAYLOAD_MAX) plen = RAWHID_EXT_PAYLOAD_MAX;

    uint8_t frame[RAWHID_FRAME_SIZE];
    memset(frame, 0, sizeof(frame));
    frame[0] = RAWHID_EXT_MAGIC_0;
    frame[1] = RAWHID_EXT_MAGIC_1;
    frame[2] = RAWHID_EXT_VERSION;
    frame[3] = (uint8_t)(type | RAWHID_EXT_RESPONSE);
    frame[4] = (uint8_t)(seq & 0xFF);
    frame[5] = (uint8_t)((seq >> 8) & 0xFF);
    frame[6] = plen;
    if (plen > 0) memcpy(&frame[7], payload, plen);

    uint16_t body_len = (uint16_t)(7 + plen);
    uint16_t crc = crc16_ccitt(frame, body_len);
    frame[body_len]     = (uint8_t)(crc & 0xFF);
    frame[body_len + 1] = (uint8_t)((crc >> 8) & 0xFF);

    resp_enqueue(frame, (uint16_t)(body_len + 2));
}

// 3-byte layout ACK: generation(LE) + status (0 = OK)
static void send_layout_ack(uint8_t type, uint16_t seq, uint16_t gen, uint8_t status)
{
    uint8_t payload[3] = { (uint8_t)(gen & 0xFF), (uint8_t)((gen >> 8) & 0xFF), status };
    send_ext_response(type, seq, payload, sizeof(payload));
}

static void handle_extension(const uint8_t *data, uint16_t len)
{
    if (len < 9 || data[2] != RAWHID_EXT_VERSION || data[6] > RAWHID_EXT_PAYLOAD_MAX) return;

    uint8_t plen = data[6];
    uint16_t total = (uint16_t)(9 + plen);
    if (len < total) return;

    uint16_t crc_expected = (uint16_t)(data[total - 2] | (data[total - 1] << 8));
    if (crc16_ccitt(data, (uint16_t)(total - 2)) != crc_expected) return;

    uint8_t type = data[3];
    uint16_t seq = (uint16_t)(data[4] | (data[5] << 8));
    const uint8_t *payload = &data[7];

    uint32_t now = to_ms_since_boot(get_absolute_time());
    rawhid.last_rx_ms = now;

    switch (type) {
        case RAWHID_EXT_DESCRIPTOR_META: {
            // gen(2) len(2) crc(2) active(1)
            size_t desc_len = 0;
            const uint8_t *desc = usbhid_get_mouse_desc(&desc_len);
            uint16_t gen = usbhid_get_mouse_desc_generation();

            uint8_t resp[7] = { 0 };
            resp[0] = (uint8_t)(gen & 0xFF);
            resp[1] = (uint8_t)((gen >> 8) & 0xFF);
            if (desc != NULL && desc_len > 0 && desc_len <= 256) {
                uint16_t desc_crc = crc16_ccitt(desc, (uint16_t)desc_len);
                resp[2] = (uint8_t)(desc_len & 0xFF);
                resp[3] = (uint8_t)((desc_len >> 8) & 0xFF);
                resp[4] = (uint8_t)(desc_crc & 0xFF);
                resp[5] = (uint8_t)((desc_crc >> 8) & 0xFF);
                resp[6] = 1;  // active
            }
            send_ext_response(RAWHID_EXT_DESCRIPTOR_META, seq, resp, sizeof(resp));
            break;
        }

        case RAWHID_EXT_DESCRIPTOR_CHUNK: {
            // request: offset(2) → response: gen(2) offset(2) chunk(≤44)
            if (plen < 2) break;
            uint16_t offset = (uint16_t)(payload[0] | (payload[1] << 8));

            size_t desc_len = 0;
            const uint8_t *desc = usbhid_get_mouse_desc(&desc_len);
            uint16_t gen = usbhid_get_mouse_desc_generation();

            uint8_t resp[4 + 44];
            resp[0] = (uint8_t)(gen & 0xFF);
            resp[1] = (uint8_t)((gen >> 8) & 0xFF);
            resp[2] = (uint8_t)(offset & 0xFF);
            resp[3] = (uint8_t)((offset >> 8) & 0xFF);

            uint8_t chunk_len = 0;
            if (desc != NULL && offset < desc_len) {
                size_t remaining = desc_len - offset;
                chunk_len = (remaining > 44) ? 44 : (uint8_t)remaining;
                memcpy(&resp[4], desc + offset, chunk_len);
            }
            send_ext_response(RAWHID_EXT_DESCRIPTOR_CHUNK, seq, resp,
                              (uint8_t)(4 + chunk_len));
            break;
        }

        case RAWHID_EXT_LAYOUT_BEGIN: {
            // payload: gen(2) report_id(1) wire_len(1) flags(1) xmin/max ymin/max(16)
            if (plen < 21) break;
            uint16_t gen = (uint16_t)(payload[0] | (payload[1] << 8));
            uint16_t cur_gen = usbhid_get_mouse_desc_generation();
            if (gen != cur_gen) {
                send_layout_ack(type, seq, cur_gen, 1);
                break;
            }
            // Our injection engine formats reports itself — remember the
            // negotiated wire length only to satisfy INJECTION_STATUS.
            rawhid.layout_generation = gen;
            rawhid.layout_wire_len = payload[3];
            rawhid.layout_committed = false;
            send_layout_ack(type, seq, gen, 0);
            break;
        }

        case RAWHID_EXT_LAYOUT_FIELD: {
            // payload: gen(2) role(1) bit_offset(2) bit_size(1) — accepted as-is
            if (plen < 6) break;
            uint16_t gen = (uint16_t)(payload[0] | (payload[1] << 8));
            uint8_t status = (gen == rawhid.layout_generation) ? 0 : 1;
            send_layout_ack(type, seq, usbhid_get_mouse_desc_generation(), status);
            break;
        }

        case RAWHID_EXT_LAYOUT_COMMIT: {
            if (plen < 2) break;
            uint16_t gen = (uint16_t)(payload[0] | (payload[1] << 8));
            if (gen == rawhid.layout_generation) {
                rawhid.layout_committed = true;
                send_layout_ack(type, seq, gen, 0);
            } else {
                send_layout_ack(type, seq, usbhid_get_mouse_desc_generation(), 1);
            }
            break;
        }

        case RAWHID_EXT_INJECTION_STATUS: {
            // gen(2) active(1) hasTemplate(1) observedLen(1) wireLen(1)
            uint8_t resp[6];
            uint16_t gen = usbhid_get_mouse_desc_generation();
            resp[0] = (uint8_t)(gen & 0xFF);
            resp[1] = (uint8_t)((gen >> 8) & 0xFF);
            resp[2] = rawhid.layout_committed ? 1 : 0;
            resp[3] = 1;
            resp[4] = rawhid.layout_wire_len;
            resp[5] = rawhid.layout_wire_len;
            send_ext_response(RAWHID_EXT_INJECTION_STATUS, seq, resp, sizeof(resp));
            break;
        }

        default:
            break;
    }
}

//--------------------------------------------------------------------+
// Public API
//--------------------------------------------------------------------+

void rawhid_control_init(void)
{
    memset(&rawhid, 0, sizeof(rawhid));
    flash_get_unique_id(rawhid.device_uid);
}

void rawhid_control_reset(void)
{
    uint32_t now = to_ms_since_boot(get_absolute_time());

    // Drop any buttons held by the protocol so a reconnect can't leave them stuck
    release_all_forced_buttons(now);

    rawhid.handshaked = false;
    rawhid.sw_buttons_mask = 0;
    rawhid.layout_generation = 0;
    rawhid.layout_wire_len = 0;
    rawhid.layout_committed = false;
    rawhid.resp_head = rawhid.resp_tail = 0;
}

void rawhid_control_handle_output(const uint8_t *data, uint16_t len)
{
    if (data == NULL || len == 0) return;

    if (len >= 2 && data[0] == RAWHID_EXT_MAGIC_0 && data[1] == RAWHID_EXT_MAGIC_1) {
        handle_extension(data, len);
    } else {
        handle_legacy(data, len);
    }
}

void rawhid_control_task(void)
{
    // 30 s silence timeout — mirrors the firmware-side behaviour of the
    // original SmartUniversalMouse implementation.
    if (rawhid.handshaked) {
        uint32_t now = to_ms_since_boot(get_absolute_time());
        if ((now - rawhid.last_rx_ms) >= RAWHID_CONNECTION_TIMEOUT_MS) {
            rawhid_control_reset();
        }
    }

    // Drain the response queue onto the interrupt IN endpoint
    uint8_t inst = usbhid_get_rawhid_instance();
    while (rawhid.resp_tail != rawhid.resp_head) {
        const uint8_t *frame = rawhid.resp_queue[rawhid.resp_tail];
        if (!tud_hid_n_report(inst, 0, frame, RAWHID_FRAME_SIZE)) {
            break;  // endpoint busy — retry next loop iteration
        }
        rawhid.resp_tail = (rawhid.resp_tail + 1) & RAWHID_RESP_QUEUE_MASK;
    }
}
