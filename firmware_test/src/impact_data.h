#pragma once
#include <stdint.h>

// Dữ liệu va chạm tổng hợp - mô phỏng các tình huống va chạm thực tế
// Mỗi mẫu là raw int16 từ MPU6500 (±4g, 8192 LSB/g)

extern const int IMPACT_SAMPLES;

extern const int16_t impact_ax[];
extern const int16_t impact_ay[];
extern const int16_t impact_az[];
extern const uint8_t impact_label[]; // luôn = 1
