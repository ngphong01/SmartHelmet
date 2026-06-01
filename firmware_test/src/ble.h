#pragma once
#include <Arduino.h>

// Khởi tạo BLE, Nordic UART
void ble_init();

// Gửi bytes qua notify (dùng cho logger / IMU)
void ble_send_bytes(const uint8_t *data, size_t len);

// Gửi chuỗi text đơn giản (debug, IMPACT, v.v.)
void ble_send_text(const char *s);

// App gửi "START" / "STOP" → dùng nếu muốn stream IMU
bool ble_is_stream_on();

// App gửi "ACK" → user bấm "Tôi ổn"
bool ble_take_ack(); // trả true đúng 1 lần rồi tự clear

// App gửi "SOS" → user bấm "Gửi cứu hộ"
bool ble_take_sos(); // trả true đúng 1 lần rồi tự clear

// App gửi "TEST_IMPACT" → giả lập va chạm để test
bool ble_take_test_impact();
