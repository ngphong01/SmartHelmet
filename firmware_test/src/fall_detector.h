#pragma once
#include <Arduino.h>

// ============================================================
// FALL DETECTOR - Phát hiện ngã dựa trên góc nghiêng + gyro
// ============================================================
// Kết hợp: Impact (peak_g) + Tilt angle + Angular velocity
// để phân biệt va chạm thật vs rung động thông thường.

// Kết quả phát hiện ngã
struct FallResult
{
    float pitchDeg;      // góc pitch hiện tại
    float rollDeg;       // góc roll hiện tại
    float angularVelDps; // độ lớn vận tốc góc (°/s)
    float tiltMagnitude; // độ nghiêng tổng hợp sqrt(pitch² + roll²)
    bool isTilted;       // góc nghiêng > ngưỡng
    bool isFallen;       // KẾT LUẬN: có ngã không
    const char *reason;  // lý do (debug)
};

// =========================
// CẤU HÌNH NGƯỠNG
// =========================

// Ngưỡng góc nghiêng để coi là ngã (độ)
// Mặc định 55° cho thực tế. Hạ xuống 35° để dễ test.
#define FALL_TILT_THRESHOLD_DEG 55.0f

// Ngưỡng vận tốc góc để coi là chuyển động ngã (°/s)
// Mặc định 120°/s. Hạ xuống 60°/s để dễ test.
#define FALL_GYRO_THRESHOLD_DPS 120.0f

// Thời gian giữ trạng thái ngã (ms) - để xác nhận không phải rung thoáng qua
#define FALL_HOLD_MS 1500

// =========================
// API
// =========================

// Khởi tạo fall detector
void fall_detector_init();

// Cập nhật với dữ liệu IMU mới (đã scale về g và dps)
// Gọi mỗi lần có sample IMU mới
void fall_detector_update(float ax_g, float ay_g, float az_g,
                          float gx_dps, float gy_dps, float gz_dps);

// Kiểm tra trạng thái ngã hiện tại
// Trả về con trỏ tới FallResult (nullptr nếu chưa có dữ liệu)
const FallResult *fall_detector_check();

// Có đang trong trạng thái ngã không
bool fall_detector_is_fallen();

// Reset trạng thái ngã (sau khi xử lý xong)
void fall_detector_reset();

// Lấy pitch/roll mới nhất
float fall_detector_get_pitch();
float fall_detector_get_roll();
float fall_detector_get_angular_velocity();
