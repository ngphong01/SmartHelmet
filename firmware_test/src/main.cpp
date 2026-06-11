#include <Arduino.h>
#include <math.h>

#include "config.h"
#include "imu.h"
#include "gps.h"
#include "fft_features.h"
#include "ml_model.h"
#include "train_on_device.h"
#include "data_recorder.h"
#include "ble.h"
#include "ble_manager.h"
#include "telegram.h"
#include "secrets.h"

// === GIẢI PHÁP MỚI (GP1-5) ===
#include "impact_buffer.h"        // GP1: Buffer + Retry
#include "wifi_manager.h"         // GP4: WiFi đa SSID
#include "ble_mesh.h"             // GP5: BLE Mesh broadcast
#include "gps_selector.h"         // GP6: GPS Selector - luân phiên NEO-6M & Phone
#include "ble_emergency_beacon.h" // GP7: BLE Emergency Beacon - phát SOS không cần ghép đôi

// === TÍNH NĂNG NÂNG CAO (NHÓM 2) ===
#include "fall_detector.h" // 2.1: Phát hiện ngã (pitch/roll/gyro)
#include "ride_state.h"    // 2.3: State machine IDLE/RIDING/IMPACT/FALLEN
#include "gps_cache.h"     // 2.4: Cache GPS cuối cùng
#include "log_system.h"    // Hệ thống log thống nhất

// =========================
// CẤU HÌNH DETECTION
// =========================

// 🔧 TEST MODE: bật để dễ test va chạm (chỉ cần lắc nhẹ)
//    KHI NÀO XONG THÌ SET = false ĐỂ TRÁNH BÁO ĐỘNG GIẢ!
static const bool TEST_MODE = false;

// Số mẫu cho FFT (phải KHỚP với N_FFT trong fft_features.cpp)
static const int WIN_N = 512;
// STEP = WIN_N/2 = 256 được dùng trong run_detection_window (trượt cửa sổ HALF)
static const float ACCEL_SENS = ACCEL_SENS_16G; // từ config.h (2048.0f cho ±16g)

// Ngưỡng phát hiện va chạm
static const float IMPACT_THRESH = 0.85f;    // AI probability threshold
static const float PEAK_G_MIN = 2.0f;        // G-peak tối thiểu để AI xem xét
static const float BRUTE_FORCE_G_MIN = 5.0f; // G-peak > mức này → bypass AI, kích hoạt luôn!
static const uint8_t IMPACT_CONFIRM_WINDOWS = 1;
static const uint32_t IMPACT_DEBOUNCE_MS = 5000;

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
static uint32_t lastRidePrintMs = 0;
static uint8_t impactCandidateCount = 0;

// Gyro data cho fall detector (dps)
static float last_gx_dps = 0.0f;
static float last_gy_dps = 0.0f;
static float last_gz_dps = 0.0f;

// Stats tracking cho periodic summary
static float gPeakGMax30s = 0.0f;
static float gAiPMax30s = 0.0f;
static uint32_t gImpactCount = 0;
static uint32_t gFallCount = 0;
static uint32_t gSosCount = 0;
static uint32_t gFalsePosCount = 0;
static bool gFallHandled = false; // chặn cascade từ cả impact & fall detector
static uint32_t gFallCooldownStartMs = 0;
static uint32_t lastStatsPrintMs = 0;
static const uint32_t STATS_PERIOD_MS = 60000; // 60 giây

// =========================
// HÀM HỖ TRỢ
// =========================

// Lấy 1 mẫu IMU, cập nhật gBuf với |a| (đơn vị g)
static void sampleImuAndUpdateBuffer()
{
    float ax_raw, ay_raw, az_raw;
    float gx_raw, gy_raw, gz_raw;

    imu_read(ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw);

    // Ghi vào recorder (để thu thập dữ liệu thật)
    recorder_push((int16_t)ax_raw, (int16_t)ay_raw, (int16_t)az_raw);

    // scale về g
    float ax_g = ax_raw / ACCEL_SENS;
    float ay_g = ay_raw / ACCEL_SENS;
    float az_g = az_raw / ACCEL_SENS;

    float gmag = sqrtf(ax_g * ax_g + ay_g * ay_g + az_g * az_g);
    // Lọc nhiễu: < 0.3g là noise. Clamp tại 16g (max của ±16g scale) thay vì discard
    if (!isfinite(gmag) || gmag < 0.3f)
    {
        return;
    }
    if (gmag > 16.0f)
    {
        gmag = 16.0f;
    }

    last_ax_g = ax_g;
    last_ay_g = ay_g;
    last_az_g = az_g;

    // Scale gyro về dps (±500 dps full-scale → 65.5 LSB/dps, dùng hằng từ config.h)
    last_gx_dps = gx_raw / GYRO_SENS_500;
    last_gy_dps = gy_raw / GYRO_SENS_500;
    last_gz_dps = gz_raw / GYRO_SENS_500;

    // Cập nhật fall detector với dữ liệu IMU đầy đủ
    fall_detector_update(ax_g, ay_g, az_g, last_gx_dps, last_gy_dps, last_gz_dps);

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
        // Cập nhật GPS cache + ride state machine
        gps_cache_update(fix.lat, fix.lon, fix.speedKmh, fix.hdop, fix.satellites);
        ride_state_update_gps(fix.speedKmh, true);
        // Cập nhật GPS Selector → để luân phiên với Phone GPS
        gps_selector_update_neo6m(fix.lat, fix.lon, fix.speedKmh, fix.satellites, fix.hdop);
    }
    else
    {
        // GPS chưa có fix mới → vẫn báo cho ride state (dùng dữ liệu cũ)
        ride_state_update_gps(lastGps.speedKmh, lastGps.valid);
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
        LOG_DBG("GPS", "lat=%.6f lon=%.6f speed=%.1f sats=%d hdop=%.2f age=%lums",
                lastGps.lat, lastGps.lon, lastGps.speedKmh,
                lastGps.satellites, lastGps.hdop, (unsigned long)ageMs);
    }
    else
    {
        LOG_DBG("GPS", "Chua co fix, dang tim ve tinh...");
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

    // ===== 4) Quyết định impact (có gate bởi ride state) =====

    // Chỉ chạy detection khi đang RIDING (hoặc IDLE - dự phòng)
    bool should_detect = ride_state_should_detect();

    // ===== BRUTE-FORCE: G-peak quá lớn → bypass AI, kích hoạt ngay =====
    bool brute_force = (g_peak > BRUTE_FORCE_G_MIN);

    bool impact_candidate = should_detect && (brute_force || (strong_motion && (p > IMPACT_THRESH)));
    if (impact_candidate)
    {
        if (impactCandidateCount < IMPACT_CONFIRM_WINDOWS)
        {
            impactCandidateCount++;
            if (impactCandidateCount == 1)
            {
                LOG_WARN("DETECT", "Ung vien: p=%.3f peak=%.2fg - cho xac nhan (%d/%d)",
                         p, g_peak, impactCandidateCount, IMPACT_CONFIRM_WINDOWS);
            }
            else
            {
                LOG_DBG("DETECT", "Cua so %d/%d: p=%.3f - giu candidate",
                        impactCandidateCount, IMPACT_CONFIRM_WINDOWS, p);
            }
        }
    }
    else
    {
        if (impactCandidateCount > 0)
        {
            LOG_DBG("DETECT", "Reject ung vien: p=%.3f < %.3f (xac suat giam)",
                    p, IMPACT_THRESH);
        }
        impactCandidateCount = 0;
    }

    // Reject log: có motion mạnh nhưng không đủ điều kiện
    if (strong_motion && !impact_candidate && impactCandidateCount == 0)
    {
        if (!should_detect)
        {
            // Chỉ log mỗi 30s để tránh spam
            static uint32_t lastRejectLog = 0;
            if (nowMs - lastRejectLog > 30000)
            {
                lastRejectLog = nowMs;
                LOG_DBG("DETECT", "Reject: peak=%.2fg nhung dang %s (chua chay xe)",
                        g_peak, ride_state_name());
            }
        }
        else if (inCooldown)
        {
            LOG_DBG("DETECT", "Reject: debounce %lu ms chua het (con %lu ms)",
                    (unsigned long)IMPACT_DEBOUNCE_MS,
                    (unsigned long)(IMPACT_DEBOUNCE_MS - (nowMs - lastImpactMs)));
        }
        else
        {
            // 👈 THÊM DÒNG NÀY: log khi AI từ chối nhưng G-peak mạnh
            LOG_WARN("DETECT", "AI REJECT: p=%.3f < %.3f | peak=%.2fg (du manh nhung AI khong nhan dien)",
                     p, IMPACT_THRESH, g_peak);
        }
    }

    if (impact_candidate && impactCandidateCount >= IMPACT_CONFIRM_WINDOWS && !inCooldown)
    {
        lastImpactMs = nowMs;
        gFallHandled = true; // chặn cascade từ fall detector
        gFallCooldownStartMs = nowMs;
        impactCandidateCount = 0;
        gImpactCount++;

        // Cập nhật state machine
        ride_state_trigger_impact();

        // ============================================
        // 2.1: Fall Detection - kiểm tra ngã
        // ============================================
        const FallResult *fall = fall_detector_check();
        bool isFall = fall && fall->isFallen;

        if (isFall)
        {
            gFallCount++;
            ride_state_trigger_fall();
            LOG_RAW("\n");
            LOG_RAW("************************************************************\n");
            LOG_RAW("***           PHAT HIEN NGA XE!                         ***\n");
            LOG_RAW("***   p=%.3f  peak=%.2fg  pitch=%.1f  roll=%.1f        ***\n",
                    p, g_peak, fall->pitchDeg, fall->rollDeg);
            LOG_RAW("************************************************************\n");
            LOG_RAW("\n");
        }
        else
        {
            LOG_RAW("\n");
            LOG_RAW("************************************************************\n");
            LOG_RAW("***           PHAT HIEN VA CHAM!                         ***\n");
            LOG_RAW("***   p=%.3f  peak=%.2fg  %s                             ***\n",
                    p, g_peak,
                    brute_force ? "BRUTE-FORCE (bypass AI)" : "AI confirmed");
            LOG_RAW("************************************************************\n");
            LOG_RAW("\n");
        }

        // ============================================
        // 2.4: GPS fallback - dùng cache nếu NEO-6M chưa fix
        // ============================================
        float alertLat, alertLon, alertSpeed;
        bool alertGpsValid;
        if (lastGps.valid)
        {
            alertLat = lastGps.lat;
            alertLon = lastGps.lon;
            alertSpeed = lastGps.speedKmh;
            alertGpsValid = true;
        }
        else
        {
            const GpsCacheEntry *cache = gps_cache_get();
            if (cache && cache->valid)
            {
                alertLat = cache->lat;
                alertLon = cache->lon;
                alertSpeed = cache->speedKmh;
                alertGpsValid = true;
                char ageBuf[32];
                gps_cache_format_age(ageBuf, sizeof(ageBuf));
                LOG_WARN("GPS", "Dung vi tri uoc tinh: %s", ageBuf);
            }
            else
            {
                alertLat = 0.0f;
                alertLon = 0.0f;
                alertSpeed = 0.0f;
                alertGpsValid = false;
            }
        }

        // ============================================
        // GP1: Buffer + Retry
        // ============================================
        impact_buffer_push(alertLat, alertLon, alertSpeed, p, g_peak, alertGpsValid);

        // 🔴 Gửi Telegram (WiFi trực tiếp)
        telegram_send_impact_alert(alertLat, alertLon, alertSpeed, p, g_peak, alertGpsValid);

        // Nếu là fall → gửi thêm tin nhắn Telegram riêng
        if (isFall)
        {
            char fallMsg[256];
            snprintf(fallMsg, sizeof(fallMsg),
                     "🛑 *PHAT HIEN NGA XE!*\n"
                     "Goc nghieng: %.0f°\n"
                     "Van toc goc: %.0f °/s\n"
                     "AI xac suat va cham: %.1f%%\n"
                     "⚠️ Co the nguoi di xe da nga!\n"
                     "Kiem tra ngay!",
                     fall->tiltMagnitude, fall->angularVelDps, p * 100.0f);
            telegram_send_message(fallMsg);
        }

        // ============================================
        // Gửi ngay impact_alert JSON qua BLE cho Flutter gọi điện
        // ============================================
        if (ble_is_connected())
        {
            char bleJson[384];
            snprintf(bleJson, sizeof(bleJson),
                     "{\"type\":\"impact_alert\",\"schema_version\":2,\"helmet_id\":\"H001\","
                     "\"gps\":{\"lat\":%.6f,\"lon\":%.6f,\"speed_kmh\":%.2f,\"valid\":%s},"
                     "\"impact\":{\"detected\":true,\"ai_p\":%.3f,\"peak_g\":%.3f,\"event_type\":\"%s\"},"
                     "\"ts\":%lu}\n",
                     alertLat, alertLon, alertSpeed,
                     alertGpsValid ? "true" : "false",
                     p, g_peak,
                     isFall ? "fall_detected" : "impact_detected",
                     (unsigned long)nowMs);
            ble_manager_send_text(bleJson);
            LOG_INFO("BLE", "Da gui impact_alert JSON (AI: p=%.3f peak=%.2fg, %lu bytes)",
                     p, g_peak, (unsigned long)strlen(bleJson));
        }

        // ============================================
        // GP5: BLE Mesh broadcast
        // ============================================
        ble_mesh_broadcast_impact(alertLat, alertLon, g_peak, p, alertGpsValid, false);

        // ============================================
        // GP7: BLE Emergency Beacon - SOS cho phone lạ
        // ============================================
        emergency_beacon_start(alertLat, alertLon, g_peak, p, isFall,
                               alertGpsValid ? lastGps.satellites : 0);
    }
    else if ((nowMs - lastDebugPrintMs) >= DEBUG_PRINT_PERIOD_MS || impact_candidate)
    {
        lastDebugPrintMs = nowMs;
        // Track peak stats
        if (g_peak > gPeakGMax30s)
            gPeakGMax30s = g_peak;
        if (p > gAiPMax30s)
            gAiPMax30s = p;
        LOG_DBG("CHECK", "p=%.3f peak=%.2fg cand=%d cnt=%d | BF=%s (thres=%.1fg)",
                p, g_peak, impact_candidate ? 1 : 0, impactCandidateCount,
                brute_force ? "YES" : "no", BRUTE_FORCE_G_MIN);
    }

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

    // ===== BOOT INFO =====
    printBootInfo();
    printConfigInfo();

    // Khởi tạo IMU
    imu_init();
    LOG_OK("IMU", "Cam bien IMU san sang");

    // Khởi tạo GPS
    gps_init();
    LOG_OK("GPS", "Module GPS san sang, UART2 @ 9600 baud");

    // Khởi tạo BLE (dual-phone + heartbeat)
    ble_init();

    // ============================================
    // GIẢI PHÁP 1: Impact Buffer (EEPROM persist)
    // ============================================
    impact_buffer_init();

    // ============================================
    // GIẢI PHÁP 4: WiFi Manager đa SSID
    // Thêm WiFi mặc định từ secrets.h
    // ============================================
    wifi_manager_init();
    wifi_manager_add_network(WIFI_SSID, WIFI_PASS, 0); // priority 0 = cao nhất
    wifi_manager_print_networks();

    // Khởi tạo WiFi + Telegram Bot
    telegram_init();

    // ============================================
    // GP5: BLE Mesh Scanner
    // ============================================
    ble_mesh_init();

    // ============================================
    // 2.1: Fall Detector
    // ============================================
    fall_detector_init();

    // ============================================
    // 2.3: Ride State Machine
    // ============================================
    ride_state_init();

    // ============================================
    // 2.4: GPS Cache (RTC memory)
    // ============================================
    gps_cache_init();

    // ============================================
    // GP6: GPS Selector - luân phiên NEO-6M / Phone
    // ============================================
    gps_selector_init();

    // ============================================
    // GP7: BLE Emergency Beacon
    // ============================================
    emergency_beacon_init();

    // Khởi tạo model logistic
    model_init(gModel);

    // Train offline trên dữ liệu trong training_data.cpp
    run_offline_training(gModel);

    LOG_INFO("AI", "Model Logistic Regression sau train:");
    LOG_RAW("  b = %.6f\n", gModel.b);
    for (int i = 0; i < FEAT_DIM; ++i)
    {
        LOG_RAW("  w[%d] = %.6f\n", i, gModel.w[i]);
    }

    // Chuẩn bị cho sampling realtime
    lastSampleUs = micros();
    gBufIdx = 0;
    lastImpactMs = 0;
    lastDebugPrintMs = 0;
    lastGpsPrintMs = 0;
    impactCandidateCount = 0;

    // Khởi tạo data recorder
    recorder_init();

    LOG_INFO("SYS", "Setup hoan tat. Vao loop chinh.");
    LOG_RAW("\n");
}

void loop()
{
    uint32_t nowUs = micros();
    uint32_t nowMs = millis();

    // ============================================
    // 1) IMU Sampling + GPS @ SAMPLE_RATE_HZ (1000Hz)
    // ============================================
    if (nowUs - lastSampleUs >= PERIOD_US)
    {
        lastSampleUs += PERIOD_US;

        sampleImuAndUpdateBuffer();
        updateGpsSnapshot();
        updateGpsAge();
        printGpsStatus(nowMs);

        // ===== Gửi JSON telemetry nâng cao qua BLE (tần suất theo sample rate, tự throttle) =====
        {
            static uint32_t lastBleTelemetryMs = 0;
            if (nowMs - lastBleTelemetryMs >= 200) // gửi BLE telemetry mỗi 200ms
            {
                lastBleTelemetryMs = nowMs;

                // GPS Selector: lấy dữ liệu từ nguồn tốt nhất (NEO-6M hoặc Phone)
                double selLat, selLon;
                float selSpeed, selHdop;
                uint8_t selSats;
                bool selValid = gps_selector_get_fix(selLat, selLon, selSpeed, selSats, selHdop);
                const char *gpsSource = gps_selector_source_name();
                int gpsScore = gps_selector_get_score();

                const FallResult *fallStatus = fall_detector_check();
                float pitch = fallStatus ? fallStatus->pitchDeg : 0.0f;
                float roll = fallStatus ? fallStatus->rollDeg : 0.0f;
                float angVel = fallStatus ? fallStatus->angularVelDps : 0.0f;

                char json[768];
                snprintf(json, sizeof(json),
                         "{\"type\":\"telemetry\",\"schema_version\":5,\"helmet_id\":\"H001\",\"device_type\":\"helmet\","
                         "\"gps\":{\"lat\":%.6f,\"lon\":%.6f,\"speed_kmh\":%.2f,\"satellites\":%u,\"hdop\":%.2f,\"source\":\"%s\",\"score\":%d},"
                         "\"imu\":{\"pitch_deg\":%.1f,\"roll_deg\":%.1f,\"angular_vel_dps\":%.1f},"
                         "\"impact\":{\"detected\":%s,\"ai_p\":%.3f,\"peak_g\":%.3f,\"confidence\":%.3f,\"event_type\":\"%s\"},"
                         "\"state\":{\"ride_state\":\"%s\",\"fall_detected\":%s,\"uptime_s\":%lu},"
                         "\"firmware\":{\"version\":\"2.2.0\",\"build\":\"esp32-brute-force\"},"
                         "\"time\":{\"utc\":\"%04u-%02u-%02uT%02u:%02u:%02uZ\"},"
                         "\"ts\":\"%lu\"}",
                         selValid ? selLat : (lastGps.valid ? lastGps.lat : 0.0),
                         selValid ? selLon : (lastGps.valid ? lastGps.lon : 0.0),
                         selValid ? selSpeed : lastGps.speedKmh,
                         selValid ? selSats : lastGps.satellites,
                         selValid ? selHdop : lastGps.hdop,
                         gpsSource,
                         gpsScore,
                         pitch, roll, angVel,
                         "false",
                         0.0f, 0.0f, 0.0f,
                         "none",
                         ride_state_name(),
                         fall_detector_is_fallen() ? "true" : "false",
                         (unsigned long)(nowMs / 1000),
                         (unsigned)lastGps.year,
                         (unsigned)lastGps.month,
                         (unsigned)lastGps.day,
                         (unsigned)lastGps.hour,
                         (unsigned)lastGps.minute,
                         (unsigned)lastGps.second,
                         (unsigned long)(nowMs));

                if (ble_is_connected())
                {
                    ble_send_text(json);
                }
            }
        }
    }

    // ============================================
    // 2) Impact Detection @ INFER_PERIOD_MS (500ms)
    // ============================================
    {
        static uint32_t lastInferMs = 0;
        if (nowMs - lastInferMs >= INFER_PERIOD_MS)
        {
            lastInferMs = nowMs;
            run_detection_window();
        }
    }

    // ============================================
    // 3) Fall Detector DIRECT CHECK (không phụ thuộc ML)
    //    Chạy độc lập với impact detection để bắt được
    //    mọi tình huống ngã thực sự.
    // ============================================
    {
        static uint32_t lastFallCheckMs = 0;
        static uint32_t fallDebounceStartMs = 0;
        static bool fallPending = false;

        // Kiểm tra fall detector mỗi 200ms
        if (nowMs - lastFallCheckMs >= 200)
        {
            lastFallCheckMs = nowMs;
            const FallResult *fr = fall_detector_check();
            // gFallHandled: đã xử lý fall này, chặn re-trigger cho đến khi người dùng ACK "TÔI ỔN"
            if (fr && fr->isFallen && !gFallHandled)
            {
                if (!fallPending)
                {
                    fallPending = true;
                    fallDebounceStartMs = nowMs;
                    LOG_WARN("FALL", "Phat hien nghi nga: tilt=%.1f gyro=%.1f - cho xac nhan...",
                             fr->tiltMagnitude, fr->angularVelDps);
                }
                // Xác nhận sau 800ms duy trì trạng thái ngã
                else if (nowMs - fallDebounceStartMs > 800)
                {
                    // Chỉ trigger nếu chưa trong cooldown impact
                    if (nowMs - lastImpactMs > IMPACT_DEBOUNCE_MS)
                    {
                        lastImpactMs = nowMs;
                        gFallCount++;
                        fallPending = false;

                        ride_state_trigger_fall();

                        LOG_RAW("\n");
                        LOG_RAW("************************************************************\n");
                        LOG_RAW("***    FALL DETECTOR: PHAT HIEN NGA XE!                 ***\n");
                        LOG_RAW("***    tilt=%.1f°  gyro=%.1f dps  pitch=%.1f  roll=%.1f ***\n",
                                fr->tiltMagnitude, fr->angularVelDps, fr->pitchDeg, fr->rollDeg);
                        LOG_RAW("************************************************************\n");
                        LOG_RAW("\n");

                        // Gửi Telegram alert
                        float lat = lastGps.valid ? lastGps.lat : 0.0f;
                        float lon = lastGps.valid ? lastGps.lon : 0.0f;
                        float spd = lastGps.valid ? lastGps.speedKmh : 0.0f;
                        telegram_send_impact_alert(lat, lon, spd, 0.0f, 0.0f, lastGps.valid);

                        char fallMsg[256];
                        snprintf(fallMsg, sizeof(fallMsg),
                                 "🛑 *PHAT HIEN NGA XE! (Fall Detector)*\n"
                                 "Goc nghieng: %.0f°\n"
                                 "Van toc goc: %.0f dps\n"
                                 "⚠️ Kiem tra ngay!",
                                 fr->tiltMagnitude, fr->angularVelDps);
                        telegram_send_message(fallMsg);

                        // BLE Mesh broadcast
                        ble_mesh_broadcast_impact(lat, lon, 0.0f, 0.0f, lastGps.valid, true);

                        // Buffer
                        impact_buffer_push(lat, lon, spd, 0.0f, 0.0f, lastGps.valid);

                        // Gửi ngay impact_alert JSON qua BLE cho Flutter gọi điện
                        if (ble_is_connected())
                        {
                            char bleJson[384];
                            snprintf(bleJson, sizeof(bleJson),
                                     "{\"type\":\"impact_alert\",\"schema_version\":2,\"helmet_id\":\"H001\","
                                     "\"gps\":{\"lat\":%.6f,\"lon\":%.6f,\"speed_kmh\":%.2f,\"valid\":%s},"
                                     "\"impact\":{\"detected\":true,\"ai_p\":%.3f,\"peak_g\":%.2f,\"event_type\":\"fall_detected\","
                                     "\"tilt_deg\":%.1f,\"gyro_dps\":%.1f},"
                                     "\"ts\":%lu}\n",
                                     lat, lon, spd,
                                     lastGps.valid ? "true" : "false",
                                     gAiPMax30s, gPeakGMax30s,
                                     fr->tiltMagnitude, fr->angularVelDps,
                                     (unsigned long)nowMs);
                            ble_manager_send_text(bleJson);
                            LOG_INFO("BLE", "Da gui impact_alert JSON (%lu bytes)", (unsigned long)strlen(bleJson));
                        }

                        // Chặn re-trigger: chỉ trigger lại khi fall_detector hồi phục
                        gFallHandled = true;
                        gFallCooldownStartMs = nowMs;
                    }
                }
            }
            else if (!fr || !fr->isFallen)
            {
                // Hết trạng thái ngã → reset tất cả
                if (fallPending)
                {
                    LOG_DBG("FALL", "Huy fall pending - da dung day");
                }
                fallPending = false;
                gFallHandled = false;
                fallDebounceStartMs = 0;
            }
            // else: isFallen=true nhưng fallHandled đang chặn → không làm gì, giữ trạng thái
        }
    }

    // ============================================
    // 4) Telegram: xử lý tin nhắn đến
    // ============================================
    telegram_loop();

    // ============================================
    // GIẢI PHÁP 2+3: Heartbeat + BLE maintenance
    // ============================================
    ble_manager_heartbeat_loop();

    // ============================================
    // GP6: GPS Selector - đánh giá & luân phiên nguồn
    // ============================================
    {
        static uint32_t lastGpsSelEvalMs = 0;
        if (nowMs - lastGpsSelEvalMs >= 1000) // đánh giá mỗi 1 giây
        {
            lastGpsSelEvalMs = nowMs;
            gps_selector_evaluate();
        }
    }
    // ============================================
    // In trạng thái GPS Selector định kỳ (mỗi 30s)
    // ============================================
    {
        static uint32_t lastGpsSelPrintMs = 0;
        if (nowMs - lastGpsSelPrintMs > 30000)
        {
            lastGpsSelPrintMs = nowMs;
            gps_selector_print();
        }
    }

    // ============================================
    // In trạng thái Ride State định kỳ (mỗi 30s)
    // ============================================
    {
        if (nowMs - lastRidePrintMs > 30000)
        {
            lastRidePrintMs = nowMs;
            ride_state_print();
        }
    }

    // ============================================
    // DEBUG: In IMU pitch/roll/tilt mỗi 2 giây
    // (để xác nhận cảm biến IMU đang hoạt động)
    // ============================================
    {
        static uint32_t lastImuPrintMs = 0;
        if (nowMs - lastImuPrintMs > 2000)
        {
            lastImuPrintMs = nowMs;
            const FallResult *fr = fall_detector_check();
            if (fr)
            {
                LOG_INFO("IMU", "pitch=%.1f roll=%.1f tilt=%.1f gyro=%.1f dps | fallen=%s tilted=%s",
                         fr->pitchDeg, fr->rollDeg, fr->tiltMagnitude, fr->angularVelDps,
                         fr->isFallen ? "YES" : "no",
                         fr->isTilted ? "YES" : "no");
            }
        }
    }

    // ============================================
    // GIẢI PHÁP 4: WiFi auto-connect/scan
    // ============================================
    wifi_manager_loop();

    // ============================================
    // GIẢI PHÁP 5: BLE Mesh scan (nhận beacon từ mũ khác)
    // ============================================
    ble_mesh_scan_loop();

    // ============================================
    // GIẢI PHÁP 1: Retry gửi impact events pending
    // ============================================
    {
        static uint32_t lastRetryMs = 0;

        if (nowMs - lastRetryMs >= IMPACT_RETRY_INTERVAL_MS)
        {
            lastRetryMs = nowMs;

            // Retry qua BLE (nếu có phone kết nối)
            if (ble_is_connected())
            {
                const ImpactEvent *evt = impact_buffer_get_pending_ble();
                if (evt)
                {
                    // Gửi JSON impact event qua BLE
                    char json[384];
                    snprintf(json, sizeof(json),
                             "{\"type\":\"impact_alert\",\"schema_version\":2,\"helmet_id\":\"H001\","
                             "\"gps\":{\"lat\":%.6f,\"lon\":%.6f,\"speed_kmh\":%.2f,\"valid\":%s},"
                             "\"impact\":{\"detected\":true,\"ai_p\":%.3f,\"peak_g\":%.3f,\"retry\":%d},"
                             "\"ts\":%lu}",
                             evt->lat, evt->lon, evt->speedKmh,
                             evt->gpsValid ? "true" : "false",
                             evt->aiProbability, evt->peakG, evt->retryCount,
                             (unsigned long)evt->timestamp);

                    if (ble_manager_send_text(json))
                    {
                        impact_buffer_mark_ble_sent();
                    }
                }
            }

            // Retry qua WiFi (nếu có WiFi)
            if (wifi_manager_is_connected())
            {
                const ImpactEvent *evt = impact_buffer_get_pending_wifi();
                if (evt)
                {
                    static bool firstFlushWifi = true;
                    if (firstFlushWifi)
                    {
                        LOG_INFO("IMPACT_BUF", "Phat hien WiFi co lai, gui su kien queue...");
                        firstFlushWifi = false;
                    }
                    telegram_send_impact_alert(
                        evt->lat, evt->lon, evt->speedKmh,
                        evt->aiProbability, evt->peakG,
                        evt->gpsValid);
                    impact_buffer_mark_wifi_sent();
                    LOG_OK("IMPACT_BUF", "Su kien da gui Telegram thanh cong");
                }
            }
        }
    }

    // ============================================
    // Periodic stats summary (60s)
    // ============================================
    {
        if (nowMs - lastStatsPrintMs > STATS_PERIOD_MS)
        {
            lastStatsPrintMs = nowMs;
            printStatsSummary(
                nowMs / 1000, ESP.getFreeHeap(),
                wifi_manager_is_connected(),
                wifi_manager_is_connected() ? wifi_manager_get_ip().c_str() : "none",
                ble_manager_connected_count(),
                lastGps.valid, lastGps.satellites,
                lastGps.valid ? lastGps.lat : 0.0,
                lastGps.valid ? lastGps.lon : 0.0,
                gPeakGMax30s, gAiPMax30s,
                ride_state_name(), lastGps.speedKmh,
                gImpactCount, gFallCount, gSosCount, gFalsePosCount);
            gPeakGMax30s = 0.0f;
            gAiPMax30s = 0.0f;
        }
    }

    // 🔴 XỬ LÝ SOS TỪ APP
    if (ble_take_sos())
    {
        gSosCount++;
        LOG_WARN("SOS", "Nhan SOS tu app!");
        ride_state_trigger_sos();

        telegram_send_message("🆘 *SOS! Nguoi dung da kich hoat cuu ho thu cong!*\nCan kiem tra ngay lap tuc!");

        ble_mesh_broadcast_impact(
            lastGps.valid ? lastGps.lat : 0.0f,
            lastGps.valid ? lastGps.lon : 0.0f,
            0.0f, 1.0f,
            lastGps.valid, true);
    }

    // ✅ XỬ LÝ ACK TỪ APP (TÔI ỔN)
    if (ble_take_ack())
    {
        LOG_OK("ACK", "Nguoi dung xac nhan an toan!");
        ride_state_ack();
        fall_detector_reset();
        emergency_beacon_stop(); // GP7: tat beacon SOS
    }

    // 🧪 XỬ LÝ TEST IMPACT - giả lập va chạm
    if (ble_take_test_impact())
    {
        LOG_WARN("TEST", "Kich hoat va cham gia lap!");
        telegram_send_impact_alert(
            lastGps.valid ? lastGps.lat : 0.0f,
            lastGps.valid ? lastGps.lon : 0.0f,
            lastGps.speedKmh,
            0.95f, 3.5f,
            lastGps.valid);
    }

    // 📋 XỬ LÝ LỆNH SERIAL - Data Recorder + New Modules
    if (Serial.available())
    {
        char cmd = Serial.read();
        switch (cmd)
        {
        case 'i':
        case 'I':
            // Đánh dấu impact: 500ms trước + 1000ms sau
            Serial.println("\n[RECORDER] Danh dau IMPACT! (500ms truoc + 1000ms sau)");
            recorder_mark_impact(500, 1000);
            break;
        case 'r':
        case 'R':
            Serial.printf("\n[RECORDER] Xuat du lieu (%u mau)...\n", (unsigned)recorder_count());
            recorder_dump_to_serial();
            break;
        case 'c':
        case 'C':
            recorder_clear();
            break;
        // === LỆNH MỚI CHO CÁC GIẢI PHÁP ===
        case 'b':
        case 'B':
            // In trạng thái Impact Buffer
            impact_buffer_print_status();
            break;
        case 'w':
        case 'W':
            // In trạng thái WiFi Manager
            wifi_manager_print_networks();
            break;
        case 'm':
        case 'M':
            // In trạng thái BLE Mesh
            ble_mesh_print_status();
            break;
        case 'd':
        case 'D':
            // In trạng thái Ride State + Fall Detector
            ride_state_print();
            {
                const FallResult *f = fall_detector_check();
                if (f)
                {
                    Serial.printf("[FALL_DET] pitch=%.1f roll=%.1f angVel=%.1f tiltMag=%.1f tilted=%d fallen=%d\n",
                                  f->pitchDeg, f->rollDeg, f->angularVelDps,
                                  f->tiltMagnitude, f->isTilted ? 1 : 0, f->isFallen ? 1 : 0);
                }
                const GpsCacheEntry *c = gps_cache_get();
                if (c && c->valid)
                {
                    Serial.printf("[GPS_CACHE] lat=%.6f lon=%.6f age=%lu s\n",
                                  c->lat, c->lon, (unsigned long)gps_cache_age_seconds());
                }
            }
            break;
        case 's':
        case 'S':
            // In trạng thái BLE connections
            {
                BleConnectionStats stats = ble_manager_get_stats();
                Serial.println("===== BLE CONNECTION STATS =====");
                Serial.printf("  Connected phones: %d\n", ble_manager_connected_count());
                Serial.printf("  Primary connected: %s\n", ble_manager_is_primary_connected() ? "YES" : "NO");
                Serial.printf("  Total disconnects: %lu\n", (unsigned long)stats.totalDisconnects);
                Serial.printf("  Total reconnects: %lu\n", (unsigned long)stats.totalReconnects);
                Serial.printf("  Uptime: %lu s\n", (unsigned long)stats.uptimeSeconds);
                for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
                {
                    const BlePhoneInfo *info = ble_manager_get_phone_info(i);
                    if (info && info->state >= BLE_CONNECTED)
                    {
                        Serial.printf("  Phone%d: handle=%d, state=%d, primary=%d\n",
                                      i, info->connHandle, (int)info->state, info->isPrimary ? 1 : 0);
                    }
                }
            }
            break;
        default:
            break;
        }
    }
}
