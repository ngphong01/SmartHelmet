#pragma once
#include <stdint.h>

// ============================================================
// DATA RECORDER - Ghi lại dữ liệu IMU thật để làm training data
// ============================================================

// Dung lượng buffer: 5 giây @ 1000Hz = 5000 mẫu
#define RECORDER_BUFFER_SIZE 5000

// Khởi tạo recorder
void recorder_init();

// Ghi 1 mẫu IMU raw vào ring buffer
void recorder_push(int16_t ax, int16_t ay, int16_t az);

// Đánh dấu impact: đánh dấu N mẫu trước và M mẫu sau thời điểm hiện tại là label=1
// preMs: số ms trước thời điểm hiện tại
// postMs: số ms sau thời điểm hiện tại
void recorder_mark_impact(uint32_t preMs, uint32_t postMs);

// In dữ liệu đã ghi ra Serial dưới dạng C array (để copy vào training_data.cpp)
// Chỉ in những mẫu đã được đánh dấu impact (label=1) và một số mẫu normal xung quanh
void recorder_dump_to_serial();

// Trả về số mẫu đã ghi
uint32_t recorder_count();

// Xóa toàn bộ buffer
void recorder_clear();
