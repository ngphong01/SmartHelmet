#pragma once
#include <Arduino.h>
#include <WiFi.h>

// ============================================================
// LOG SYSTEM — Unified logging for SmartHelmet firmware
// ============================================================
// Format: [timestamp_ms][LEVEL][MODULE] message
// LEVEL: OK, ERR, WARN, INFO, DBG
// ============================================================

// --- Log Levels (lvl_ prefix to avoid NimBLE conflict) ---
enum LogLevel : uint8_t
{
    LVL_ERROR = 0,
    LVL_WARN = 1,
    LVL_INFO = 2,
    LVL_DEBUG = 3
};

// Global log level (có thể thay đổi qua BLE)
extern LogLevel gLogLevel;

// --- MACROS ---
// Timestamp prefix tự động: [millis() 8 chữ số]

#define LOG_OK(mod, fmt, ...)                                                         \
    do                                                                                \
    {                                                                                 \
        if (gLogLevel >= LVL_INFO)                                                    \
            Serial.printf("[%08lu][OK][%s] " fmt "\n", millis(), mod, ##__VA_ARGS__); \
    } while (0)
#define LOG_ERR(mod, fmt, ...)                                                         \
    do                                                                                 \
    {                                                                                  \
        if (gLogLevel >= LVL_ERROR)                                                    \
            Serial.printf("[%08lu][ERR][%s] " fmt "\n", millis(), mod, ##__VA_ARGS__); \
    } while (0)
#define LOG_WARN(mod, fmt, ...)                                                         \
    do                                                                                  \
    {                                                                                   \
        if (gLogLevel >= LVL_WARN)                                                      \
            Serial.printf("[%08lu][WARN][%s] " fmt "\n", millis(), mod, ##__VA_ARGS__); \
    } while (0)
#define LOG_INFO(mod, fmt, ...)                                                   \
    do                                                                            \
    {                                                                             \
        if (gLogLevel >= LVL_INFO)                                                \
            Serial.printf("[%08lu][%s] " fmt "\n", millis(), mod, ##__VA_ARGS__); \
    } while (0)
#define LOG_DBG(mod, fmt, ...)                                                         \
    do                                                                                 \
    {                                                                                  \
        if (gLogLevel >= LVL_DEBUG)                                                    \
            Serial.printf("[%08lu][DBG][%s] " fmt "\n", millis(), mod, ##__VA_ARGS__); \
    } while (0)

// Impact banner — luôn in, không phụ thuộc log level
#define LOG_IMPACT_BANNER(...) Serial.printf(__VA_ARGS__)

// Raw print (không timestamp) — dùng cho multi-line output
#define LOG_RAW(fmt, ...) Serial.printf(fmt, ##__VA_ARGS__)

// ============================================================
// SYSTEM INFO FUNCTIONS
// ============================================================

// Convert reset reason to readable string
const char *getResetReasonStr();

// Print boot banner with chip info, MAC, flash, heap
void printBootInfo();

// Print current configuration
void printConfigInfo();

// Print periodic stats summary (gọi mỗi 60s)
void printStatsSummary(uint32_t uptimeS, uint32_t freeHeap,
                       bool wifiConnected, const char *wifiSsid,
                       int bleConnCount, bool gpsValid,
                       uint8_t sats, float lat, float lon,
                       float peakGMax, float aiPMax,
                       const char *rideState, float speedKmh,
                       uint32_t impactCount, uint32_t fallCount,
                       uint32_t sosCount, uint32_t falsePosCount);
