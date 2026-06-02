#pragma once
#include <Arduino.h>

// ============================================================
// GPS CACHE - Lưu vị trí GPS cuối cùng vào RTC memory
// ============================================================
// RTC memory tồn tại qua deep sleep (nhưng mất khi reset cứng).
// Dùng để: khi va chạm xảy ra mà GPS chưa có fix mới,
// vẫn gửi được vị trí "ước tính, X giây trước".

struct GpsCacheEntry
{
    bool valid;
    double lat;
    double lon;
    float speedKmh;
    float hdop;
    uint8_t satellites;
    uint32_t timestampMs; // millis() lúc lưu
};

// =========================
// API
// =========================

// Khởi tạo (đọc cache từ RTC memory nếu có)
void gps_cache_init();

// Lưu vị trí GPS mới vào cache
void gps_cache_update(double lat, double lon, float speedKmh,
                      float hdop, uint8_t satellites);

// Đọc cache - trả về vị trí cuối cùng
const GpsCacheEntry *gps_cache_get();

// Tuổi của cache (giây)
uint32_t gps_cache_age_seconds();

// Cache có hợp lệ không
bool gps_cache_is_valid();

// Format cache thành text (dùng trong Telegram message)
void gps_cache_format_age(char *buf, size_t bufSize);
