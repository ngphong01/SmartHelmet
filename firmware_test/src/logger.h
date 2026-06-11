#pragma once
#include <Arduino.h>

// ============================================================
// LEGACY LOGGER - Đã được thay thế bởi log_system.h
// Giữ lại để tương thích ngược, gọi xuống log_system
// ============================================================

void logger_begin();
void logger_loop();
void logger_start();
void logger_stop();
void logger_set_marker(uint8_t marker);