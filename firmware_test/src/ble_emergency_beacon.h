#pragma once
#include <Arduino.h>
#include <NimBLEDevice.h>

// ============================================================
// BLE EMERGENCY BEACON - Phát tín hiệu cấp cứu qua Advertising
// ============================================================
// KHÔNG cần ghép đôi. Mọi điện thoại gần đó (có app SmartHelmet)
// đều nhận được tín hiệu SOS và có thể gọi cấp cứu giúp.

// UUID riêng cho emergency beacon (16-bit)
#define EMERGENCY_BEACON_SERVICE_UUID 0xE911

// Manufacturer ID (dùng ID giả, thay bằng ID thật nếu có)
#define EMERGENCY_MANUFACTURER_ID 0x06E1

// =========================
// DỮ LIỆU BEACON
// =========================

struct EmergencyBeaconData
{
    bool active;
    double lat;
    double lon;
    float peakG;
    float aiProbability;
    bool isFall; // true = ngã, false = va chạm
    uint8_t satellites;
    uint32_t timestamp; // millis() lúc phát
};

// =========================
// API
// =========================

// Khởi tạo beacon (chuẩn bị advertising data, chưa bật)
void emergency_beacon_init();

// Bật phát beacon khẩn cấp
void emergency_beacon_start(double lat, double lon, float peakG,
                            float aiProbability, bool isFall,
                            uint8_t satellites);

// Tắt beacon
void emergency_beacon_stop();

// Cập nhật dữ liệu GPS mới vào beacon đang phát
void emergency_beacon_update_gps(double lat, double lon, uint8_t satellites);

// Có đang phát không
bool emergency_beacon_is_active();

// In trạng thái
void emergency_beacon_print();
