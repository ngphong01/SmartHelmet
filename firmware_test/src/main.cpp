#include <Arduino.h>
#include <math.h>

#include "config.h"
#include "imu.h"
#include "gps.h"
#include "fft_features.h"
#include "ml_model.h"
#include "train_on_device.h"
#include "ble.h"
#include "telegram.h"

// =========================
// CẤU HÌNH DETECTION
// =========================

// 🔧 TEST MODE: bật để dễ test va chạm (chỉ cần lắc nhẹ)
//    KHI NÀO XONG THÌ SET = false ĐỂ TRÁNH BÁO ĐỘNG GIẢ!
static const bool TEST_MODE = true;

// Số mẫu cho FFT (phải KHỚP với N_FFT trong fft_features.cpp)
static const int WIN_N = 512;
static const int STEP = WIN_N / 2;             // overlap 50%
static const float ACCEL_SENS = ACCEL_SENS_4G; // từ config.h (8192.0f)

// Ngưỡng xác suất để coi là impact
static const float IMPACT_THRESH = TEST_MODE ? 0.30f : 0.97f;

static const float PEAK_G_MIN = TEST_MODE ? 1.2f : 2.8f;

// Thời gian chống dính (debounce) cho impact, ms
static const uint32_t IMPACT_DEBOUNCE_MS = 5000;
static const uint8_t IMPACT_CONFIRM_WINDOWS = 2;
static const uint32_t DEBUG_PRINT_PERIOD_MS = 2000;
static const uint32_t GPS_PRINT_PERIOD_MS = 5000;

// =========================
// BIẾN TOÀN CỤC
// =========================

static LogisticModel gModel;

// buffer trượt chứa độ lớn gia tốc |a| (g)
static float gBuf[WIN_N];
static int gBufIdx = 0;

// lưu accel raw / g mới nhất (cho 3 feature cuối)
static float last_ax_g = 0.0f;
static float last_ay_g = 0.0f;
static float last_az_g = 0.0f;
static GpsFix lastGps;

static uint32_t lastSampleUs = 0;
static uint32_t lastImpactMs = 0;
static uint32_t lastDebugPrintMs = 0;
static uint32_t lastGpsPrintMs = 0;
static uint8_t impactCandidateCount = 0;

// =========================
// HÀM HỖ TRỢ
// =========================

// Lấy 1 mẫu IMU, cập nhật gBuf với |a| (đơn vị g)
static void sampleImuAndUpdateBuffer()
{
    float ax_raw, ay_raw, az_raw;
    float gx_raw, gy_raw, gz_raw;

    imu_read(ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw);

    // scale về g
    float ax_g = ax_raw / ACCEL_SENS;
    float ay_g = ay_raw / ACCEL_SENS;
    float az_g = az_raw / ACCEL_SENS;

    float gmag = sqrtf(ax_g * ax_g + ay_g * ay_g + az_g * az_g);
    if (!isfinite(gmag) || gmag < 0.2f || gmag > 7.0f)
    {
        return;
    }

    last_ax_g = ax_g;
    last_ay_g = ay_g;
    last_az_g = az_g;

    // cho vào buffer
    if (gBufIdx < WIN_N)
    {
        gBuf[gBufIdx++] = gmag;
    }
}

static void updateGpsSnapshot()
{
    gps_poll();
    GpsFix fix;
    if (gps_get_fix(fix))
    {
        lastGps = fix;
    }
}

static void updateGpsAge()
{
    if (!lastGps.valid)
        return;
    const uint32_t ageMs = millis() - lastGps.lastUpdateMs;
    if (ageMs > 10000)
    {
        lastGps.valid = false;
    }
}

static void printGpsStatus(uint32_t nowMs)
{
    if ((nowMs - lastGpsPrintMs) < GPS_PRINT_PERIOD_MS)
        return;
    lastGpsPrintMs = nowMs;

    if (lastGps.valid)
    {
        uint32_t ageMs = nowMs - lastGps.lastUpdateMs;
        Serial.printf("[GPS][OK] lat=%.6f lon=%.6f toc_do=%.2f_kmh ve_tinh=%u hdop=%.2f tuoi=%lums\n",
                      lastGps.lat,
                      lastGps.lon,
                      lastGps.speedKmh,
                      (unsigned)lastGps.satellites,
                      lastGps.hdop,
                      (unsigned long)ageMs);
    }
    else
    {
        Serial.println("[GPS][CHO] Chua co toa do. Dua GPS ra ngoai troi/cua so va doi 1-3 phut");
    }
}

static void run_detection_window()
{
    if (gBufIdx < WIN_N)
        return;

    // ===== 0) TÍNH GIA TỐC ĐỈNH TRONG CỬA SỔ =====
    float g_peak = 0.0f;
    for (int i = 0; i < WIN_N; ++i)
    {
        if (gBuf[i] > g_peak)
            g_peak = gBuf[i];
    }
    bool strong_motion = (g_peak > PEAK_G_MIN);

    // ===== 1) FFT feature 5 dải tần =====
    float fft_feat[5];
    compute_fft_features(gBuf, WIN_N, fft_feat);

    // ===== 2) 3 feature cuối = accel (g) tại sample mới nhất =====
    float feat[FEAT_DIM]; // FEAT_DIM = 8: 5 FFT + 3 accel
    feat[0] = fft_feat[0];
    feat[1] = fft_feat[1];
    feat[2] = fft_feat[2];
    feat[3] = fft_feat[3];
    feat[4] = fft_feat[4];
    feat[5] = last_ax_g;
    feat[6] = last_ay_g;
    feat[7] = last_az_g;

    // ===== 3) Dự đoán xác suất impact =====
    float p = logistic_predict(gModel, feat);

    uint32_t nowMs = millis();
    bool inCooldown = (nowMs - lastImpactMs) < IMPACT_DEBOUNCE_MS;

    // ===== 4) Quyết định impact_flag =====
    int impact_flag = 0;
    bool impact_candidate = strong_motion && (p > IMPACT_THRESH);
    if (impact_candidate)
    {
        if (impactCandidateCount < IMPACT_CONFIRM_WINDOWS)
        {
            impactCandidateCount++;
        }
    }
    else
    {
        impactCandidateCount = 0;
    }

    if (impact_candidate && impactCandidateCount >= IMPACT_CONFIRM_WINDOWS && !inCooldown)
    {
        impact_flag = 1;
        lastImpactMs = nowMs;
        impactCandidateCount = 0;
        Serial.printf("[CANH BAO][VA CHAM] p=%.3f dinh_g=%.3f\n", p, g_peak);

        // 🔴 Gửi cảnh báo qua Telegram
        telegram_send_impact_alert(
            lastGps.valid ? lastGps.lat : 0.0f,
            lastGps.valid ? lastGps.lon : 0.0f,
            lastGps.speedKmh,
            p,
            g_peak,
            lastGps.valid);
    }
    else if ((nowMs - lastDebugPrintMs) >= DEBUG_PRINT_PERIOD_MS || impact_candidate)
    {
        lastDebugPrintMs = nowMs;
        Serial.printf("[KIEM TRA] p=%.3f dinh_g=%.3f ung_vien=%d dem=%u\n",
                      p, g_peak, impact_candidate ? 1 : 0, impactCandidateCount);
    }

    updateGpsSnapshot();
    updateGpsAge();
    printGpsStatus(nowMs);

    // ===== 5) Gửi JSON ML + GPS qua BLE mỗi cửa sổ 512ms =====
    char json[256];
    snprintf(json, sizeof(json),
             "{\"type\":\"telemetry\",\"schema_version\":2,\"helmet_id\":\"H001\",\"device_type\":\"helmet\","
             "\"gps\":{\"lat\":%.6f,\"lon\":%.6f,\"speed_kmh\":%.2f,\"satellites\":%u,\"hdop\":%.2f},"
             "\"impact\":{\"detected\":%s,\"ai_p\":%.3f,\"peak_g\":%.3f,\"confidence\":%.3f},"
             "\"firmware\":{\"version\":\"1.0.0\",\"build\":\"esp32-gps\"},"
             "\"time\":{\"utc\":\"%04u-%02u-%02uT%02u:%02u:%02uZ\"},"
             "\"ts\":\"%lu\"}",
             lastGps.valid ? lastGps.lat : 0.0,
             lastGps.valid ? lastGps.lon : 0.0,
             lastGps.speedKmh,
             lastGps.satellites,
             lastGps.hdop,
             impact_flag ? "true" : "false",
             p,
             g_peak,
             p,
             (unsigned)lastGps.year,
             (unsigned)lastGps.month,
             (unsigned)lastGps.day,
             (unsigned)lastGps.hour,
             (unsigned)lastGps.minute,
             (unsigned)lastGps.second,
             (unsigned long)(millis()));

    ble_send_text(json);

    // ===== 6) Trượt cửa sổ: giữ lại 256 mẫu cuối =====
    const int HALF = WIN_N / 2;
    for (int i = 0; i < HALF; ++i)
    {
        gBuf[i] = gBuf[i + HALF];
    }
    gBufIdx = HALF;
}

// =========================
// SETUP & LOOP CHÍNH
// =========================

void setup()
{
    Serial.begin(115200);
    delay(800);
    Serial.println();
    Serial.println("=== [MU BAO HIEM] Che do ML: train + phat hien va cham ===");

    // Khởi tạo IMU
    imu_init();
    Serial.println("[OK][IMU] Cam bien IMU san sang");

    // Khởi tạo GPS
    gps_init();
    Serial.println("[OK][GPS] Module GPS san sang");

    // Khởi tạo BLE nếu bạn muốn gửi cảnh báo
    ble_init();

    // Khởi tạo WiFi + Telegram Bot
    telegram_init();

    // Khởi tạo model logistic
    model_init(gModel);

    // Train offline trên dữ liệu trong training_data.cpp
    run_offline_training(gModel);

    Serial.println("[AI] Thong so model sau khi train:");
    Serial.print("b = ");
    Serial.println(gModel.b, 6);
    for (int i = 0; i < FEAT_DIM; ++i)
    {
        Serial.print("w[");
        Serial.print(i);
        Serial.print("] = ");
        Serial.println(gModel.w[i], 6);
    }

    // Chuẩn bị cho sampling realtime
    lastSampleUs = micros();
    gBufIdx = 0;
    lastImpactMs = 0;
    lastDebugPrintMs = 0;
    lastGpsPrintMs = 0;
    impactCandidateCount = 0;

    Serial.println("[RUN] Bat dau phat hien va cham realtime");
}

void loop()
{
    uint32_t nowUs = micros();

    // Lấy mẫu đúng tần số SAMPLE_RATE_HZ (ở config.h bạn set = 1000)
    if (nowUs - lastSampleUs >= PERIOD_US)
    {
        lastSampleUs += PERIOD_US;

        sampleImuAndUpdateBuffer();
        run_detection_window();
    }

    // 🔴 XỬ LÝ SOS TỪ APP
    if (ble_take_sos())
    {
        Serial.println("[SOS] Nhan SOS tu app - bat coi/LED va giu trang thai su co");
    }

    // 🧪 XỬ LÝ TEST IMPACT - giả lập va chạm
    if (ble_take_test_impact())
    {
        Serial.println("[TEST] Kich hoat va cham gia lap!");
        telegram_send_impact_alert(
            lastGps.valid ? lastGps.lat : 0.0f,
            lastGps.valid ? lastGps.lon : 0.0f,
            lastGps.speedKmh,
            0.95f, // giả lập xác suất 95%
            3.5f,  // giả lập đỉnh G 3.5g
            lastGps.valid);
    }
}
