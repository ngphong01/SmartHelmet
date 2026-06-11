#include "fall_detector.h"
#include <math.h>

// =========================
// BIẾN TOÀN CỤC
// =========================

static FallResult gFallResult;
static bool gHasData = false;
static bool gIsFallen = false;
static uint32_t gFallStartMs = 0;
static uint32_t gLastTiltedMs = 0;

// =========================
// KHỞI TẠO
// =========================

void fall_detector_init()
{
    memset(&gFallResult, 0, sizeof(gFallResult));
    gHasData = false;
    gIsFallen = false;
    gFallStartMs = 0;
    gLastTiltedMs = 0;
    Serial.println("[FALL_DET] Khoi tao xong");
}

// =========================
// CẬP NHẬT
// =========================

void fall_detector_update(float ax_g, float ay_g, float az_g,
                          float gx_dps, float gy_dps, float gz_dps)
{
    // ---- Tính Pitch & Roll từ accelerometer ----
    // Pitch: góc nghiêng trước-sau (forward/backward tilt)
    // Roll:  góc nghiêng trái-phải (side tilt)
    float dp = sqrtf(ay_g * ay_g + az_g * az_g);
    float dr = sqrtf(ax_g * ax_g + az_g * az_g);

    float pitchDeg = (dp > 0.001f) ? atan2f(ax_g, dp) * 57.29578f : 0.0f;
    float rollDeg = (dr > 0.001f) ? atan2f(ay_g, dr) * 57.29578f : 0.0f;

    // ---- Tính Angular Velocity magnitude ----
    float angVel = sqrtf(gx_dps * gx_dps + gy_dps * gy_dps + gz_dps * gz_dps);

    // ---- Tính tilt magnitude ----
    float tiltMag = sqrtf(pitchDeg * pitchDeg + rollDeg * rollDeg);

    // ---- Cập nhật kết quả ----
    gFallResult.pitchDeg = pitchDeg;
    gFallResult.rollDeg = rollDeg;
    gFallResult.angularVelDps = angVel;
    gFallResult.tiltMagnitude = tiltMag;

    uint32_t now = millis();

    // Kiểm tra điều kiện ngã:
    // 1. Góc nghiêng > ngưỡng
    // 2. Vận tốc góc > ngưỡng (đang có chuyển động quay - không phải nằm yên)
    bool tilted = (tiltMag > FALL_TILT_THRESHOLD_DEG);
    bool spinning = (angVel > FALL_GYRO_THRESHOLD_DPS);

    gFallResult.isTilted = tilted;

    if (tilted)
    {
        gLastTiltedMs = now;
    }

    // Fall = tilted AND spinning (đang ngã, không phải đã nằm yên)
    // HOẶC tilted duy trì > FALL_HOLD_MS (đã ngã xong, đang nằm)

    if ((tilted && spinning) || (tilted && (now - gFallStartMs > FALL_HOLD_MS && gFallStartMs > 0)))
    {
        if (!gIsFallen)
        {
            gIsFallen = true;
            gFallStartMs = now;
            gFallResult.isFallen = true;
            gFallResult.reason = tilted && spinning ? "tilt+spin" : "sustained_tilt";

            Serial.printf("[FALL_DET][NGA!] pitch=%.1f roll=%.1f tilt=%.1f gyro=%.1f reason=%s\n",
                          pitchDeg, rollDeg, tiltMag, angVel, gFallResult.reason);
        }
        else
        {
            gFallResult.isFallen = true; // vẫn đang ngã
        }
    }
    else if (!tilted && (now - gLastTiltedMs > 2000))
    {
        // Hết ngã: đứng thẳng lại > 2s
        if (gIsFallen)
        {
            Serial.printf("[FALL_DET][HOI PHUC] Da dung day, pitch=%.1f roll=%.1f\n", pitchDeg, rollDeg);
        }
        gIsFallen = false;
        gFallResult.isFallen = false;
        gFallResult.reason = "upright";
        gFallStartMs = 0;
    }
    else
    {
        gFallResult.isFallen = gIsFallen;
    }

    gHasData = true;
}

// =========================
// TRUY VẤN
// =========================

const FallResult *fall_detector_check()
{
    if (!gHasData)
        return nullptr;
    return &gFallResult;
}

bool fall_detector_is_fallen()
{
    return gIsFallen;
}

void fall_detector_reset()
{
    gIsFallen = false;
    gFallResult.isFallen = false;
    gFallStartMs = 0;
    Serial.println("[FALL_DET] Reset trang thai nga");
}

float fall_detector_get_pitch() { return gFallResult.pitchDeg; }
float fall_detector_get_roll() { return gFallResult.rollDeg; }
float fall_detector_get_angular_velocity() { return gFallResult.angularVelDps; }
