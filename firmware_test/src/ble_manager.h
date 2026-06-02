#pragma once
#include <Arduino.h>
#include <NimBLEDevice.h>

// ============================================================
// BLE MANAGER - Giải pháp 2+3: Dual-phone + Heartbeat
// ============================================================
// Hỗ trợ:
//   - 2 kết nối BLE đồng thời (phone chính + phone dự phòng)
//   - Heartbeat mỗi 5s để kiểm tra kết nối còn sống
//   - Auto-reconnect khi mất kết nối
//   - Theo dõi trạng thái kết nối

// Số phone tối đa có thể kết nối đồng thời
#define BLE_MAX_CONNECTIONS 2

// UUID cho heartbeat service
#define BLE_HEARTBEAT_SERVICE_UUID "6E400010-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_HEARTBEAT_NOTIFY_UUID "6E400011-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_HEARTBEAT_WRITE_UUID "6E400012-B5A3-F393-E0A9-E50E24DCCA9E"

// =========================
// TRẠNG THÁI KẾT NỐI
// =========================

enum BleConnState
{
    BLE_DISCONNECTED = 0,
    BLE_CONNECTING,
    BLE_CONNECTED,
    BLE_HEARTBEAT_OK // có heartbeat → kết nối khỏe
};

struct BlePhoneInfo
{
    uint16_t connHandle;
    BleConnState state;
    uint32_t lastHeartbeatMs;  // lần cuối nhận heartbeat response
    uint32_t connectedSinceMs; // thời điểm kết nối
    bool isPrimary;            // phone chính hay dự phòng
};

struct BleConnectionStats
{
    uint32_t totalDisconnects;
    uint32_t totalReconnects;
    uint32_t lastDisconnectMs;
    uint32_t uptimeSeconds;
};

// =========================
// API
// =========================

// Khởi tạo BLE với dual-phone support
void ble_manager_init();

// Gửi dữ liệu qua BLE (tự động chọn phone đang kết nối)
// Ưu tiên phone chính, fallback phone phụ
bool ble_manager_send_text(const char *text);
bool ble_manager_send_bytes(const uint8_t *data, size_t len);

// Gửi heartbeat ping
void ble_manager_send_heartbeat();

// Kiểm tra và xử lý heartbeat timeout
// Gọi mỗi vòng loop
void ble_manager_heartbeat_loop();

// Kiểm tra có ít nhất 1 phone đang kết nối không
bool ble_manager_is_any_connected();

// Kiểm tra phone chính có đang kết nối không
bool ble_manager_is_primary_connected();

// Lấy số phone đang kết nối
int ble_manager_connected_count();

// Lấy thông tin phone
const BlePhoneInfo *ble_manager_get_phone_info(int index);

// Lấy thống kê kết nối
BleConnectionStats ble_manager_get_stats();

// =========================
// CÁC GETTERS TRẠNG THÁI (giữ nguyên API cũ)
// =========================

bool ble_is_stream_on();
bool ble_take_ack();
bool ble_take_sos();
bool ble_take_test_impact();

// =========================
// CÁC HẰNG SỐ
// =========================

#define BLE_HEARTBEAT_INTERVAL_MS 5000 // gửi heartbeat mỗi 5s
#define BLE_HEARTBEAT_TIMEOUT_MS 15000 // timeout nếu không nhận pong 15s
#define BLE_RECONNECT_DELAY_MS 2000    // delay giữa các lần thử reconnect
#define BLE_ADV_INTERVAL_MS 100        // advertising interval
