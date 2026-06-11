#pragma once
#include <Arduino.h>

// ============================================================
// BUZZER - Còi cảnh báo vật lý ngoài mũ bảo hiểm
// ============================================================
// GPIO 25 → chân (+) buzzer (loại active 5V qua transistor)
// Chân (-) buzzer → GND

// Khởi tạo buzzer
void buzzer_init();

// Bật buzzer liên tục (va chạm)
void buzzer_impact_beep();

// Bật chuỗi SOS Morse: ... --- ... (khi ngã/bất tỉnh)
// Gọi liên tục trong loop, tự quản lý timing
void buzzer_sos_loop();

// Tắt buzzer
void buzzer_stop();

// Buzzer có đang kêu không
bool buzzer_is_active();

// Bắt đầu pattern SOS
void buzzer_sos_start();

// Dừng pattern SOS
void buzzer_sos_stop();
