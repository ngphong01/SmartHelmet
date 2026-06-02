#include "ride_state.h"

// =========================
// BIẾN TOÀN CỤC
// =========================

static HelmetState gState = HelmetState::IDLE;
static HelmetState gPrevState = HelmetState::IDLE;
static uint32_t gStateEnterMs = 0;
static uint32_t gLastMovingMs = 0;
static uint32_t gRideCandidateMs = 0;
static bool gRideCandidate = false;
static float gLastSpeedKmh = 0.0f;

// =========================
// KHỞI TẠO
// =========================

void ride_state_init()
{
    gState = HelmetState::IDLE;
    gPrevState = HelmetState::IDLE;
    gStateEnterMs = millis();
    gLastMovingMs = 0;
    gRideCandidateMs = 0;
    gRideCandidate = false;
    gLastSpeedKmh = 0.0f;

    Serial.println("[RIDE_STATE] Khoi tao - IDLE");
}

// =========================
// CẬP NHẬT GPS
// =========================

void ride_state_update_gps(float speedKmh, bool gpsValid)
{
    if (!gpsValid)
        return; // không có GPS → giữ nguyên trạng thái

    gLastSpeedKmh = speedKmh;
    uint32_t now = millis();

    switch (gState)
    {
    case HelmetState::IDLE:
        // Bắt đầu di chuyển?
        if (speedKmh > RIDE_SPEED_THRESHOLD_KMH)
        {
            if (!gRideCandidate)
            {
                gRideCandidate = true;
                gRideCandidateMs = now;
                Serial.printf("[RIDE_STATE] Ung vien RIDING: speed=%.1f km/h\n", speedKmh);
            }
            else if (now - gRideCandidateMs > RIDE_CONFIRM_MS)
            {
                // Xác nhận RIDING sau 5s duy trì tốc độ
                gPrevState = gState;
                gState = HelmetState::RIDING;
                gStateEnterMs = now;
                gRideCandidate = false;
                Serial.println("[RIDE_STATE] IDLE → RIDING");
            }
        }
        else
        {
            gRideCandidate = false;
        }
        break;

    case HelmetState::RIDING:
        // Đang đi → cập nhật thời điểm cuối cùng di chuyển
        if (speedKmh > IDLE_SPEED_THRESHOLD_KMH)
        {
            gLastMovingMs = now;
        }

        // Đứng yên quá lâu → IDLE
        if (now - gLastMovingMs > IDLE_TIMEOUT_MS)
        {
            gPrevState = gState;
            gState = HelmetState::IDLE;
            gStateEnterMs = now;
            Serial.printf("[RIDE_STATE] RIDING → IDLE (dung yen %lu s)\n",
                          (unsigned long)((now - gLastMovingMs) / 1000));
        }
        break;

    case HelmetState::IMPACT:
    case HelmetState::FALLEN:
    case HelmetState::SOS:
        // Các trạng thái khẩn cấp - không tự chuyển, cần ACK
        break;
    }
}

// =========================
// TRIGGER SỰ KIỆN
// =========================

void ride_state_trigger_impact()
{
    if (gState == HelmetState::RIDING || gState == HelmetState::IDLE)
    {
        gPrevState = gState;
        gState = HelmetState::IMPACT;
        gStateEnterMs = millis();
        Serial.println("[RIDE_STATE] → IMPACT");
    }
}

void ride_state_trigger_fall()
{
    gPrevState = gState;
    gState = HelmetState::FALLEN;
    gStateEnterMs = millis();
    Serial.println("[RIDE_STATE] → FALLEN (NGA!)");
}

void ride_state_trigger_sos()
{
    gPrevState = gState;
    gState = HelmetState::SOS;
    gStateEnterMs = millis();
    Serial.println("[RIDE_STATE] → SOS");
}

void ride_state_ack()
{
    Serial.printf("[RIDE_STATE] ACK: %s → %s\n",
                  ride_state_name(),
                  gPrevState == HelmetState::IDLE ? "IDLE" : "RIDING");

    if (gState == HelmetState::IMPACT || gState == HelmetState::FALLEN)
    {
        gState = gPrevState;
    }
    else if (gState == HelmetState::SOS)
    {
        gState = HelmetState::IDLE; // SOS xong → về IDLE
    }
    gStateEnterMs = millis();
}

// =========================
// TRUY VẤN
// =========================

HelmetState ride_state_get()
{
    return gState;
}

const char *ride_state_name()
{
    switch (gState)
    {
    case HelmetState::IDLE:
        return "IDLE";
    case HelmetState::RIDING:
        return "RIDING";
    case HelmetState::IMPACT:
        return "IMPACT";
    case HelmetState::FALLEN:
        return "FALLEN";
    case HelmetState::SOS:
        return "SOS";
    default:
        return "UNKNOWN";
    }
}

bool ride_state_should_detect()
{
    // Chỉ chạy impact detection khi đang RIDING
    // (hoặc IDLE nhưng có chuyển động nhẹ - phòng trường hợp GPS chưa kịp update)
    return (gState == HelmetState::RIDING || gState == HelmetState::IDLE);
}

void ride_state_print()
{
    uint32_t elapsed = millis() - gStateEnterMs;
    Serial.printf("[RIDE_STATE] State=%s (%lu s), Speed=%.1f km/h, Prev=%s\n",
                  ride_state_name(),
                  (unsigned long)(elapsed / 1000),
                  gLastSpeedKmh,
                  gPrevState == HelmetState::IDLE ? "IDLE" : gPrevState == HelmetState::RIDING ? "RIDING"
                                                                                               : "OTHER");
}

uint32_t ride_state_duration_ms()
{
    return millis() - gStateEnterMs;
}
