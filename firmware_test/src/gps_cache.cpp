#include "gps_cache.h"

// =========================
// RTC MEMORY
// =========================
// ESP32 có RTC_DATA_ATTR để lưu biến trong RTC slow memory
// (tồn tại qua deep sleep, mất khi reset cứng / nạp firmware mới)

static RTC_DATA_ATTR GpsCacheEntry gCache;

// =========================
// KHỞI TẠO
// =========================

void gps_cache_init()
{
    // Kiểm tra xem cache có vẻ hợp lệ không (sau deep sleep)
    if (gCache.valid)
    {
        uint32_t age = gps_cache_age_seconds();
        Serial.printf("[GPS_CACHE] Cache hop le: lat=%.6f lon=%.6f tuoi=%lu s\n",
                      gCache.lat, gCache.lon, (unsigned long)age);

        // Nếu cache quá cũ (> 30 phút) → vô hiệu
        if (age > 1800)
        {
            gCache.valid = false;
            Serial.println("[GPS_CACHE] Cache qua han (>30phut) → vo hieu");
        }
    }
    else
    {
        // Khởi tạo lần đầu
        memset(&gCache, 0, sizeof(gCache));
        Serial.println("[GPS_CACHE] Khoi tao - chua co du lieu");
    }
}

// =========================
// CẬP NHẬT
// =========================

void gps_cache_update(double lat, double lon, float speedKmh,
                      float hdop, uint8_t satellites)
{
    gCache.valid = true;
    gCache.lat = lat;
    gCache.lon = lon;
    gCache.speedKmh = speedKmh;
    gCache.hdop = hdop;
    gCache.satellites = satellites;
    gCache.timestampMs = millis();
}

// =========================
// TRUY VẤN
// =========================

const GpsCacheEntry *gps_cache_get()
{
    if (!gCache.valid)
        return nullptr;
    return &gCache;
}

uint32_t gps_cache_age_seconds()
{
    if (!gCache.valid)
        return 999999;
    uint32_t elapsed = millis() - gCache.timestampMs;
    return elapsed / 1000;
}

bool gps_cache_is_valid()
{
    return gCache.valid && (gps_cache_age_seconds() < 1800); // < 30 phút
}

void gps_cache_format_age(char *buf, size_t bufSize)
{
    uint32_t age = gps_cache_age_seconds();
    if (age < 60)
    {
        snprintf(buf, bufSize, "%lu giay truoc", (unsigned long)age);
    }
    else if (age < 3600)
    {
        snprintf(buf, bufSize, "%lu phut truoc", (unsigned long)(age / 60));
    }
    else
    {
        snprintf(buf, bufSize, "%lu gio truoc", (unsigned long)(age / 3600));
    }
}
