#pragma once
#include <Arduino.h>

// ============================================================
// RIDE STATE MACHINE - Quản lý trạng thái di chuyển
// ============================================================
// IDLE    → không di chuyển, không chạy detection
// RIDING  → đang đi xe, chạy impact detection
// IMPACT  → phát hiện va chạm, đang chờ xác nhận
// FALLEN  → va chạm + góc nghiêng lớn = đã ngã
// SOS     → người dùng kích hoạt cứu hộ thủ công

enum class HelmetState : uint8_t
{
    IDLE = 0,
    RIDING,
    IMPACT,
    FALLEN,
    SOS
};

// Cấu hình chuyển trạng thái
#define RIDE_SPEED_THRESHOLD_KMH 8.0f // tốc độ > 8 km/h → RIDING
#define IDLE_SPEED_THRESHOLD_KMH 3.0f // tốc độ < 3 km/h → có thể IDLE
#define IDLE_TIMEOUT_MS 300000        // 5 phút đứng yên → IDLE
#define RIDE_CONFIRM_MS 5000          // 5 giây duy trì tốc độ → RIDING

// =========================
// API
// =========================

// Khởi tạo state machine
void ride_state_init();

// Cập nhật với dữ liệu GPS mới
void ride_state_update_gps(float speedKmh, bool gpsValid);

// Báo có impact được phát hiện
void ride_state_trigger_impact();

// Báo có fall (ngã) được phát hiện
void ride_state_trigger_fall();

// Báo SOS từ app
void ride_state_trigger_sos();

// Xác nhận user ổn → quay về trạng thái trước đó
void ride_state_ack();

// Lấy trạng thái hiện tại
HelmetState ride_state_get();

// Tên trạng thái dạng text
const char *ride_state_name();

// Có đang trong trạng thái cần chạy detection không
bool ride_state_should_detect();

// In trạng thái ra Serial (debug)
void ride_state_print();

// Thời gian ở trạng thái hiện tại (ms)
uint32_t ride_state_duration_ms();
