#pragma once
#include <Arduino.h>

// ===== I2C & MPU6500 =====
#define SDA_PIN      21
#define SCL_PIN      22
#define MPU_ADDR     0x68

// ===== GPS (GY-NEO6MV2) =====
#define GPS_RX_PIN   16   // ESP32 RX  <- GPS TX
#define GPS_TX_PIN   17   // ESP32 TX  -> GPS RX (thường không cần)
#define GPS_BAUD     9600

// MPU6500 registers
#define REG_PWR_MGMT_1    0x6B
#define REG_ACCEL_CONFIG  0x1C
#define REG_GYRO_CONFIG   0x1B
#define REG_ACCEL_XOUT_H  0x3B
#define REG_GYRO_XOUT_H   0x43
#define REG_WHO_AM_I      0x75

#define REG_GYRO_YOUT_H   0x45
#define REG_GYRO_ZOUT_H   0x47

constexpr uint32_t INFER_PERIOD_MS = 500;

// Full-scale: ±4g => 8192 LSB/g ; ±500 dps => 65.5 LSB/(°/s)
static const float ACCEL_SENS_4G = 8192.0f;
static const float GYRO_SENS_500 = 65.5f;

// ===== BLE =====
#define BLE_DEVICE_NAME    "SmartHelmet"
#define UUID_SERVICE_IMU   "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"  // giữ kiểu Nordic UART
#define UUID_CHAR_NOTIFY   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // Notify (stream)
#define UUID_CHAR_WRITE    "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // Write (CTRL)

// ===== Logger =====
constexpr uint16_t SAMPLE_RATE_HZ = 1000;
constexpr uint8_t  BATCH          = 10;
constexpr uint32_t PERIOD_US      = 1000000UL / SAMPLE_RATE_HZ;

// ===== Impact (giữ lại nếu bạn còn dùng kênh JSON nền) =====
struct ImpactConfig {
  float accelGSpike   = 2.2f;
  float tiltDeg       = 55.0f;
  uint32_t tiltHoldMs = 1500;
  float freeFallG     = 0.5f;
  uint32_t debounceMs = 4000;
  uint32_t repeatMs   = 5000;
  float emaAlpha      = 0.25f;
};
