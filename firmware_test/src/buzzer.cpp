#include "buzzer.h"
#include "config.h"

#define BUZZER_PIN 25

// =========================
// SOS MORSE TIMING (ms)
// =========================
// S = ... (3 ngắn), O = --- (3 dài)
// dot=200ms, dash=600ms, gap giữa ký tự=200ms, gap giữa chữ=600ms

static const uint16_t SOS_DOT_MS = 200;
static const uint16_t SOS_DASH_MS = 600;
static const uint16_t SOS_GAP_CHAR = 200;
static const uint16_t SOS_GAP_WORD = 600;
static const uint16_t SOS_CYCLE_MS = 5200; // 1 chu kỳ SOS đầy đủ

// Trạng thái SOS
enum class SosPhase : uint8_t
{
    IDLE,
    S1_ON,
    S1_OFF,
    S2_ON,
    S2_OFF,
    S3_ON,
    S3_OFF, // S = ...
    O1_ON,
    O1_OFF,
    O2_ON,
    O2_OFF,
    O3_ON,
    O3_OFF, // O = ---
    S4_ON,
    S4_OFF,
    S5_ON,
    S5_OFF,
    S6_ON,
    S6_OFF, // S = ...
    WORD_GAP
};

static SosPhase gSosPhase = SosPhase::IDLE;
static uint32_t gSosPhaseStartMs = 0;
static bool gBuzzerOn = false;

// Timing cho từng phase
static uint16_t sos_phase_duration(SosPhase p)
{
    switch (p)
    {
    case SosPhase::S1_ON:
    case SosPhase::S2_ON:
    case SosPhase::S3_ON:
    case SosPhase::S4_ON:
    case SosPhase::S5_ON:
    case SosPhase::S6_ON:
        return SOS_DOT_MS;
    case SosPhase::O1_ON:
    case SosPhase::O2_ON:
    case SosPhase::O3_ON:
        return SOS_DASH_MS;
    case SosPhase::S1_OFF:
    case SosPhase::S2_OFF:
    case SosPhase::S4_OFF:
    case SosPhase::S5_OFF:
    case SosPhase::O1_OFF:
    case SosPhase::O2_OFF:
        return SOS_GAP_CHAR;
    case SosPhase::S3_OFF:
    case SosPhase::O3_OFF:
        return SOS_GAP_CHAR; // gap giữa ký tự
    case SosPhase::S6_OFF:
        return SOS_GAP_CHAR;
    case SosPhase::WORD_GAP:
        return SOS_GAP_WORD;
    default:
        return 0;
    }
}

static SosPhase sos_next_phase(SosPhase p)
{
    switch (p)
    {
    case SosPhase::IDLE:
        return SosPhase::S1_ON;
    case SosPhase::S1_ON:
        return SosPhase::S1_OFF;
    case SosPhase::S1_OFF:
        return SosPhase::S2_ON;
    case SosPhase::S2_ON:
        return SosPhase::S2_OFF;
    case SosPhase::S2_OFF:
        return SosPhase::S3_ON;
    case SosPhase::S3_ON:
        return SosPhase::S3_OFF;
    case SosPhase::S3_OFF:
        return SosPhase::O1_ON;
    case SosPhase::O1_ON:
        return SosPhase::O1_OFF;
    case SosPhase::O1_OFF:
        return SosPhase::O2_ON;
    case SosPhase::O2_ON:
        return SosPhase::O2_OFF;
    case SosPhase::O2_OFF:
        return SosPhase::O3_ON;
    case SosPhase::O3_ON:
        return SosPhase::O3_OFF;
    case SosPhase::O3_OFF:
        return SosPhase::S4_ON;
    case SosPhase::S4_ON:
        return SosPhase::S4_OFF;
    case SosPhase::S4_OFF:
        return SosPhase::S5_ON;
    case SosPhase::S5_ON:
        return SosPhase::S5_OFF;
    case SosPhase::S5_OFF:
        return SosPhase::S6_ON;
    case SosPhase::S6_ON:
        return SosPhase::S6_OFF;
    case SosPhase::S6_OFF:
        return SosPhase::WORD_GAP;
    case SosPhase::WORD_GAP:
        return SosPhase::S1_ON; // lặp lại
    }
    return SosPhase::S1_ON;
}

static bool sos_phase_is_on(SosPhase p)
{
    switch (p)
    {
    case SosPhase::S1_ON:
    case SosPhase::S2_ON:
    case SosPhase::S3_ON:
    case SosPhase::S4_ON:
    case SosPhase::S5_ON:
    case SosPhase::S6_ON:
    case SosPhase::O1_ON:
    case SosPhase::O2_ON:
    case SosPhase::O3_ON:
        return true;
    default:
        return false;
    }
}

// =========================
// API
// =========================

void buzzer_init()
{
    pinMode(BUZZER_PIN, OUTPUT);
    digitalWrite(BUZZER_PIN, LOW);
    gBuzzerOn = false;
    gSosPhase = SosPhase::IDLE;
    Serial.println("[BUZZER] Khoi tao GPIO25 - san sang");
}

void buzzer_impact_beep()
{
    // Pattern va chạm: 3 tiếng bip nhanh
    for (int i = 0; i < 3; i++)
    {
        digitalWrite(BUZZER_PIN, HIGH);
        delay(150);
        digitalWrite(BUZZER_PIN, LOW);
        if (i < 2)
            delay(100);
    }
    Serial.println("[BUZZER] BIP BIP BIP - Canh bao va cham!");
}

void buzzer_sos_start()
{
    gSosPhase = SosPhase::S1_ON;
    gSosPhaseStartMs = millis();
    Serial.println("[BUZZER] Bat dau phat SOS (... --- ...)");
}

void buzzer_sos_stop()
{
    gSosPhase = SosPhase::IDLE;
    digitalWrite(BUZZER_PIN, LOW);
    gBuzzerOn = false;
    Serial.println("[BUZZER] Dung SOS");
}

void buzzer_sos_loop()
{
    if (gSosPhase == SosPhase::IDLE)
        return;

    uint32_t now = millis();
    uint16_t dur = sos_phase_duration(gSosPhase);

    if (now - gSosPhaseStartMs >= dur)
    {
        // Chuyển phase
        gSosPhase = sos_next_phase(gSosPhase);
        gSosPhaseStartMs = now;

        // Bật/tắt buzzer theo phase mới
        bool shouldBeOn = sos_phase_is_on(gSosPhase);
        if (shouldBeOn && !gBuzzerOn)
        {
            digitalWrite(BUZZER_PIN, HIGH);
            gBuzzerOn = true;
        }
        else if (!shouldBeOn && gBuzzerOn)
        {
            digitalWrite(BUZZER_PIN, LOW);
            gBuzzerOn = false;
        }
    }
}

void buzzer_stop()
{
    buzzer_sos_stop();
    digitalWrite(BUZZER_PIN, LOW);
    gBuzzerOn = false;
}

bool buzzer_is_active()
{
    return (gSosPhase != SosPhase::IDLE);
}
