#pragma once
#include <Arduino.h>

// ============================================================
// IMPACT BUFFER - Giải pháp 1: Buffer + Retry thông minh
// ============================================================
// Khi phát hiện va chạm mà BLE mất kết nối, lưu sự kiện vào
// EEPROM/NVS. Khi điện thoại reconnect, tự động sync lại.
// Cũng gửi liên tục qua BLE trong 30-60s sau va chạm.

// Một sự kiện va chạm được lưu trữ
struct ImpactEvent
{
    uint32_t timestamp;  // millis() lúc va chạm
    float lat;           // vĩ độ (0 nếu không có GPS)
    float lon;           // kinh độ
    float speedKmh;      // tốc độ
    float aiProbability; // xác suất AI
    float peakG;         // đỉnh gia tốc
    bool gpsValid;       // GPS có hợp lệ không
    bool sentViaBle;     // đã gửi qua BLE thành công chưa
    bool sentViaWifi;    // đã gửi qua WiFi thành công chưa
    uint8_t retryCount;  // số lần đã retry
};

// Số sự kiện tối đa có thể lưu trong buffer
#define IMPACT_BUFFER_MAX 10

// Thời gian retry gửi BLE sau va chạm (ms)
#define IMPACT_RETRY_DURATION_MS 60000 // 60 giây
#define IMPACT_RETRY_INTERVAL_MS 2000  // mỗi 2 giây retry 1 lần

// Khởi tạo buffer (đọc từ NVS/EEPROM)
void impact_buffer_init();

// Lưu 1 sự kiện va chạm mới vào buffer
// Trả về true nếu lưu thành công
bool impact_buffer_push(float lat, float lon, float speedKmh,
                        float aiProbability, float peakG, bool gpsValid);

// Lấy sự kiện tiếp theo cần retry gửi qua BLE
// Trả về nullptr nếu không còn sự kiện nào cần gửi
const ImpactEvent *impact_buffer_get_pending_ble();

// Đánh dấu sự kiện hiện tại đã gửi BLE thành công
void impact_buffer_mark_ble_sent();

// Lấy sự kiện tiếp theo cần retry gửi qua WiFi
const ImpactEvent *impact_buffer_get_pending_wifi();

// Đánh dấu sự kiện hiện tại đã gửi WiFi thành công
void impact_buffer_mark_wifi_sent();

// Có sự kiện va chạm nào đang pending không?
bool impact_buffer_has_pending();

// Số sự kiện đang chờ
int impact_buffer_pending_count();

// In trạng thái buffer ra Serial (debug)
void impact_buffer_print_status();

// Xóa tất cả sự kiện đã gửi thành công (dọn dẹp)
void impact_buffer_cleanup();
