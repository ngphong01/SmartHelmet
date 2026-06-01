#pragma once
#include <Arduino.h>

// Khởi tạo WiFi + Telegram Bot
void telegram_init();

// Gửi tin nhắn văn bản qua Telegram
// Trả về true nếu gửi thành công
bool telegram_send_message(const char *message);

// Gửi cảnh báo va chạm (kèm GPS nếu có)
void telegram_send_impact_alert(float lat, float lon, float speed_kmh,
                                float ai_probability, float peak_g,
                                bool gps_valid);

// Kiểm tra và xử lý tin nhắn đến từ Telegram (nếu cần)
void telegram_loop();
