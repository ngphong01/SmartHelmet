#pragma once
#include <Arduino.h>

// ============================================================
// BLE MESH BROADCAST - Giải pháp 5: Cảnh báo lan tỏa
// ============================================================
// Sử dụng BLE Advertising để broadcast trạng thái va chạm.
// Các mũ khác trong vùng phủ (~50-100m) có thể nhận được
// và forward qua điện thoại của họ.
//
// Cách hoạt động:
// - Khi phát hiện va chạm, ESP32 bắt đầu phát BLE advertisement
//   đặc biệt chứa thông tin va chạm (giống cách AirTag hoạt động)
// - Các mũ/điện thoại khác scan thấy advertisement này
// - Nếu là điện thoại có app, app forward lên server
// - Nếu là mũ khác, mũ relay advertisement

// UUID đặc biệt cho Impact Beacon
#define BLE_IMPACT_BEACON_UUID "6E400100-B5A3-F393-E0A9-E50E24DCCA9E"

// =========================
// IMPACT BEACON DATA
// =========================

// Dữ liệu nhúng trong advertisement (tối đa 31 byte payload)
struct __attribute__((packed)) ImpactBeaconData
{
    uint8_t version;    // 1
    uint8_t flags;      // bit0=impact, bit1=gps_valid, bit2=sos
    uint32_t timestamp; // millis() lúc va chạm
    float lat;          // vĩ độ (nếu có GPS)
    float lon;          // kinh độ
    float peakG;        // đỉnh gia tốc
    float aiProb;       // xác suất AI
    uint16_t helmetId;  // ID mũ (nén)
    // Tổng: 1+1+4+4+4+4+4+2 = 24 bytes
};

// =========================
// API
// =========================

// Khởi tạo BLE Mesh Scanner (chạy song song với BLE server)
// Dùng ESP32 dual-mode: vừa BLE peripheral vừa BLE observer
void ble_mesh_init();

// Bắt đầu broadcast impact beacon
// Gọi khi phát hiện va chạm
void ble_mesh_broadcast_impact(float lat, float lon, float peakG,
                               float aiProb, bool gpsValid, bool isSos);

// Dừng broadcast
void ble_mesh_stop_broadcast();

// Quét tìm impact beacon từ các mũ khác
// Gọi định kỳ trong loop
void ble_mesh_scan_loop();

// Callback khi phát hiện impact beacon từ mũ khác
// Người dùng đăng ký callback để xử lý (ví dụ: forward qua Telegram)
typedef void (*ImpactBeaconCallback)(const ImpactBeaconData &data, int rssi);
void ble_mesh_on_beacon_detected(ImpactBeaconCallback cb);

// Có đang broadcast không
bool ble_mesh_is_broadcasting();

// In trạng thái
void ble_mesh_print_status();
