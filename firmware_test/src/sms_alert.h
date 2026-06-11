#pragma once
#include <Arduino.h>

// ============================================================
// SMS ALERT - Gửi SMS trực tiếp từ ESP32 qua SIM800L
// ============================================================
// Dùng khi: điện thoại không ở gần, không có WiFi
// SIM800L kết nối UART2 (dùng chung với GPS nếu cần, hoặc UART riêng)

// Cấu hình SIM800L
#define SIM800L_BAUD 9600
#define SIM800L_RX_PIN 26 // ESP32 RX ← SIM800L TX
#define SIM800L_TX_PIN 25 // ESP32 TX → SIM800L RX

// Số điện thoại nhận SMS khẩn cấp (2 số)
#define SMS_PHONE_1 "0868314386"
#define SMS_PHONE_2 "0365395326"

// =========================
// API
// =========================

// Khởi tạo SIM800L
void sms_alert_init();

// Gửi SMS khẩn cấp tới cả 2 số
// Trả về true nếu gửi được ít nhất 1 số
bool sms_alert_send_impact(double lat, double lon, float speedKmh,
                           float aiProb, float peakG, bool gpsValid);

// Gửi SMS văn bản tùy ý
bool sms_alert_send(const char *phone, const char *message);

// Kiểm tra SIM800L có sẵn sàng không
bool sms_alert_ready();

// In trạng thái
void sms_alert_print_status();
