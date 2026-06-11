#pragma once
#include <Arduino.h>

// ============================================================
// GPS SELECTOR - Luân phiên thông minh giữa NEO-6M & Phone GPS
// ============================================================
// Chiến lược ngoài trời:
//   - Chấm điểm chất lượng từng nguồn (vệ tinh, HDOP/độ chính xác, tuổi)
//   - Chọn nguồn tốt nhất, có hysteresis 15% để tránh nhấp nháy
//   - Thời gian tối thiểu giữa 2 lần chuyển: 5 giây
//   - Khi cả 2 đều yếu → ưu tiên NEO-6M (trên đỉnh mũ, view trời tốt hơn)

enum class GpsSource : uint8_t
{
    NONE = 0,
    NEO6M,      // GPS module trên mũ
    PHONE,       // GPS từ điện thoại qua BLE
    CACHED       // Dùng cache cuối cùng (fallback)
};

struct GpsQuality
{
    bool valid;
    uint8_t satellites;
    float hdop;       // NEO-6M: HDOP (0.5-99.9); Phone: accuracy mét → quy đổi
    float speedKmh;
    double lat;
    double lon;
    uint32_t lastUpdateMs;
    uint32_t ageMs() const { return millis() - lastUpdateMs; }
};

// =========================
// CẤU HÌNH
// =========================

#define GPS_SWITCH_MIN_INTERVAL_MS  5000   // Tối thiểu 5s giữa 2 lần chuyển nguồn
#define GPS_SWITCH_HYSTERESIS_PCT   15     // Nguồn mới phải tốt hơn 15% mới chuyển
#define GPS_SOURCE_TIMEOUT_MS       15000  // Nguồn không cập nhật sau 15s → coi như mất
#define GPS_CACHE_MAX_AGE_MS        30000  // Cache quá 30s → vô hiệu

// Trọng số chấm điểm
#define GPS_SCORE_PER_SATELLITE     10     // Mỗi vệ tinh = 10 điểm
#define GPS_SCORE_HDOP_PENALTY      8      // Mỗi đơn vị HDOP trừ 8 điểm
#define GPS_SCORE_AGE_BONUS_MAX     20     // Thưởng tối đa 20 điểm cho dữ liệu mới
#define GPS_SCORE_MIN_SATS          4      // Dưới 4 vệ tinh → điểm = 0

// =========================
// API
// =========================

// Khởi tạo
void gps_selector_init();

// Cập nhật dữ liệu từ NEO-6M (gọi trong updateGpsSnapshot)
void gps_selector_update_neo6m(double lat, double lon, float speedKmh,
                                uint8_t satellites, float hdop);

// Cập nhật dữ liệu từ Phone GPS (gọi khi nhận "GPS:lat,lon,speed,sats" qua BLE)
void gps_selector_update_phone(double lat, double lon, float speedKmh,
                                uint8_t satellites, float accuracyM);

// Chọn nguồn tốt nhất → gọi mỗi vòng loop
void gps_selector_evaluate();

// =========================
// TRUY VẤN KẾT QUẢ
// =========================

// Lấy nguồn đang được chọn
GpsSource gps_selector_get_source();

// Tên nguồn dạng text
const char *gps_selector_source_name();

// Lấy dữ liệu GPS từ nguồn đang chọn
bool gps_selector_get_fix(double &lat, double &lon, float &speedKmh,
                          uint8_t &satellites, float &hdop);

// Lấy điểm chất lượng của nguồn đang chọn
int gps_selector_get_score();

// In trạng thái ra Serial (debug)
void gps_selector_print();

// Lấy thông tin chi tiết cả 2 nguồn (cho telemetry JSON)
void gps_selector_get_both(GpsQuality &neo, GpsQuality &phone);
