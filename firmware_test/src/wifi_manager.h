#pragma once
#include <Arduino.h>

// ============================================================
// WIFI MANAGER - Giải pháp 4: WiFi dự phòng đa SSID
// ============================================================
// Cho phép ESP32 tự kết nối WiFi đã lưu sẵn (nhà, quán cafe...)
// Khi có WiFi, gửi Telegram trực tiếp không cần qua điện thoại.

// Số WiFi network tối đa có thể lưu
#define WIFI_MAX_NETWORKS 5

// Thông tin 1 WiFi network
struct WiFiNetwork
{
    char ssid[33];
    char password[65];
    int8_t priority; // 0 = cao nhất, 255 = thấp nhất
    int32_t rssi;    // cập nhật khi scan
};

// Trạng thái WiFi
enum class WiFiState
{
    DISCONNECTED,
    SCANNING,
    CONNECTING,
    CONNECTED,
    ERROR
};

// =========================
// API
// =========================

// Khởi tạo WiFi manager
void wifi_manager_init();

// Thêm 1 WiFi network vào danh sách
// Trả về true nếu thêm thành công
bool wifi_manager_add_network(const char *ssid, const char *password, int8_t priority = 0);

// Xóa 1 network khỏi danh sách
bool wifi_manager_remove_network(const char *ssid);

// Quét các WiFi xung quanh và tự động kết nối network phù hợp nhất
// Gọi định kỳ trong loop
void wifi_manager_loop();

// Ép kết nối ngay (không chờ loop)
bool wifi_manager_connect_now();

// Ngắt kết nối WiFi
void wifi_manager_disconnect();

// Trạng thái hiện tại
WiFiState wifi_manager_get_state();

// Có đang kết nối WiFi không
bool wifi_manager_is_connected();

// Lấy IP hiện tại
String wifi_manager_get_ip();

// Lấy RSSI hiện tại
int wifi_manager_get_rssi();

// In danh sách network đã lưu
void wifi_manager_print_networks();

// Số network đã lưu
int wifi_manager_network_count();

// Cấu hình auto-scan interval (ms)
void wifi_manager_set_scan_interval(uint32_t intervalMs);
