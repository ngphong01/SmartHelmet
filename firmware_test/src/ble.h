#pragma once
#include <Arduino.h>

// ============================================================
// BLE - Backward-compatible wrapper for ble_manager
// ============================================================
// Các hàm cũ vẫn hoạt động, bên trong gọi ble_manager

// Khởi tạo BLE (dùng dual-phone + heartbeat)
void ble_init();

// Gửi bytes qua notify
void ble_send_bytes(const uint8_t *data, size_t len);

// Gửi chuỗi text (JSON, IMPACT, v.v.)
void ble_send_text(const char *s);

// App gửi "START" / "STOP"
bool ble_is_stream_on();

// App gửi "ACK" → user bấm "Tôi ổn"
bool ble_take_ack();

// App gửi "SOS" → user bấm "Gửi cứu hộ"
bool ble_take_sos();

// App gửi "TEST_IMPACT" → giả lập va chạm
bool ble_take_test_impact();

// ============================================================
// API MỚI - BLE Manager
// ============================================================

// Có ít nhất 1 phone đang kết nối không
bool ble_is_connected();

// Có bao nhiêu phone đang kết nối
int ble_connection_count();
