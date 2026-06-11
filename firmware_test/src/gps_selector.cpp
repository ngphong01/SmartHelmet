#include "gps_selector.h"

// =========================
// BIẾN TOÀN CỤC
// =========================

static GpsSource gActiveSource = GpsSource::NONE;
static GpsSource gPrevSource = GpsSource::NONE;
static uint32_t gLastSwitchMs = 0;

static GpsQuality gNeo6m = {false, 0, 99.9f, 0.0f, 0.0, 0.0, 0};
static GpsQuality gPhone = {false, 0, 99.9f, 0.0f, 0.0, 0.0, 0};

// Cache fix tốt cuối cùng (để fallback khi cả 2 nguồn mất)
static GpsQuality gCache = {false, 0, 99.9f, 0.0f, 0.0, 0.0, 0};

// =========================
// FORWARD DECLARATIONS
// =========================

static const char *source_name_of(GpsSource src);
static void update_cache_from(const GpsQuality &q);

// =========================
// HÀM NỘI BỘ
// =========================

// Chấm điểm chất lượng 1 nguồn GPS (càng cao càng tốt)
static int score_gps(const GpsQuality &q)
{
    if (!q.valid)
        return -1;

    if (q.satellites < GPS_SCORE_MIN_SATS)
        return 0;

    int score = 0;

    score += q.satellites * GPS_SCORE_PER_SATELLITE;

    float hdop = q.hdop;
    if (hdop < 0.5f)
        hdop = 0.5f;
    if (hdop > 20.0f)
        hdop = 20.0f;
    score -= (int)(hdop * GPS_SCORE_HDOP_PENALTY);

    uint32_t age = q.ageMs();
    if (age < 1000)
        score += GPS_SCORE_AGE_BONUS_MAX;
    else if (age < 3000)
        score += GPS_SCORE_AGE_BONUS_MAX / 2;
    else if (age < 5000)
        score += GPS_SCORE_AGE_BONUS_MAX / 4;

    if (age > GPS_SOURCE_TIMEOUT_MS)
        return -1;

    if (score < 0)
        score = 0;
    return score;
}

static bool source_usable(const GpsQuality &q)
{
    if (!q.valid)
        return false;
    if (q.ageMs() > GPS_SOURCE_TIMEOUT_MS)
        return false;
    if (q.satellites < GPS_SCORE_MIN_SATS)
        return false;
    return true;
}

static void update_cache_from(const GpsQuality &q)
{
    if (!q.valid)
        return;
    if (q.satellites < GPS_SCORE_MIN_SATS)
        return;
    gCache = q;
    gCache.lastUpdateMs = millis();
}

// =========================
// API IMPLEMENTATION
// =========================

void gps_selector_init()
{
    gActiveSource = GpsSource::NONE;
    gPrevSource = GpsSource::NONE;
    gLastSwitchMs = 0;

    gNeo6m = {false, 0, 99.9f, 0.0f, 0.0, 0.0, 0};
    gPhone = {false, 0, 99.9f, 0.0f, 0.0, 0.0, 0};
    gCache = {false, 0, 99.9f, 0.0f, 0.0, 0.0, 0};

    Serial.println("[GPS_SEL] Khoi tao GPS Selector - san sang luan phien NEO-6M <-> Phone");
}

void gps_selector_update_neo6m(double lat, double lon, float speedKmh,
                               uint8_t satellites, float hdop)
{
    gNeo6m.valid = true;
    gNeo6m.lat = lat;
    gNeo6m.lon = lon;
    gNeo6m.speedKmh = speedKmh;
    gNeo6m.satellites = satellites;
    gNeo6m.hdop = hdop;
    gNeo6m.lastUpdateMs = millis();
}

void gps_selector_update_phone(double lat, double lon, float speedKmh,
                               uint8_t satellites, float accuracyM)
{
    float hdopEquiv = accuracyM / 3.0f;
    if (hdopEquiv < 0.3f)
        hdopEquiv = 0.3f;
    if (hdopEquiv > 20.0f)
        hdopEquiv = 20.0f;

    gPhone.valid = true;
    gPhone.lat = lat;
    gPhone.lon = lon;
    gPhone.speedKmh = speedKmh;
    gPhone.satellites = satellites;
    gPhone.hdop = hdopEquiv;
    gPhone.lastUpdateMs = millis();
}

void gps_selector_evaluate()
{
    uint32_t nowMs = millis();

    const int scoreNeo = score_gps(gNeo6m);
    const int scorePhone = score_gps(gPhone);

    const bool neoUsable = source_usable(gNeo6m);
    const bool phoneUsable = source_usable(gPhone);

    // ----- Quyết định nguồn mong muốn -----
    GpsSource desired;

    if (!neoUsable && !phoneUsable)
    {
        if (gCache.valid && gCache.ageMs() < GPS_CACHE_MAX_AGE_MS)
            desired = GpsSource::CACHED;
        else
            desired = GpsSource::NONE;
    }
    else if (!neoUsable)
    {
        desired = GpsSource::PHONE;
    }
    else if (!phoneUsable)
    {
        desired = GpsSource::NEO6M;
    }
    else
    {
        if (gActiveSource == GpsSource::NONE || gActiveSource == GpsSource::CACHED)
        {
            desired = (scoreNeo >= scorePhone) ? GpsSource::NEO6M : GpsSource::PHONE;
        }
        else
        {
            const int currentScore = (gActiveSource == GpsSource::NEO6M) ? scoreNeo : scorePhone;
            const int otherScore = (gActiveSource == GpsSource::NEO6M) ? scorePhone : scoreNeo;
            const int base = (currentScore > 0) ? currentScore : 0;
            const int margin = base * GPS_SWITCH_HYSTERESIS_PCT / 100;

            if (otherScore > currentScore + margin)
                desired = (gActiveSource == GpsSource::NEO6M) ? GpsSource::PHONE : GpsSource::NEO6M;
            else
                desired = gActiveSource;
        }
    }

    // ----- Áp ràng buộc thời gian & thực hiện chuyển -----
    if (desired != gActiveSource)
    {
        const bool currentLost =
            (gActiveSource == GpsSource::NEO6M && !neoUsable) ||
            (gActiveSource == GpsSource::PHONE && !phoneUsable) ||
            (gActiveSource == GpsSource::NONE) ||
            (gActiveSource == GpsSource::CACHED);

        const bool intervalOk = (nowMs - gLastSwitchMs) >= GPS_SWITCH_MIN_INTERVAL_MS;

        if (currentLost || intervalOk)
        {
            gPrevSource = gActiveSource;
            gActiveSource = desired;
            gLastSwitchMs = nowMs;

            if (desired == GpsSource::NONE)
            {
                Serial.println("[GPS_SEL] CA 2 NGUON GPS DEU MAT (khong co cache hop le)!");
            }
            else
            {
                Serial.printf("[GPS_SEL] CHUYEN NGUON: %s -> %s | Score: NEO=%d Phone=%d\n",
                              source_name_of(gPrevSource),
                              source_name_of(gActiveSource),
                              scoreNeo, scorePhone);
            }
        }
    }

    // Cập nhật cache từ nguồn đang hoạt động
    if (gActiveSource == GpsSource::NEO6M)
        update_cache_from(gNeo6m);
    else if (gActiveSource == GpsSource::PHONE)
        update_cache_from(gPhone);
}

// =========================
// TRUY VẤN
// =========================

GpsSource gps_selector_get_source()
{
    return gActiveSource;
}

static const char *source_name_of(GpsSource src)
{
    switch (src)
    {
    case GpsSource::NEO6M:
        return "NEO-6M";
    case GpsSource::PHONE:
        return "Phone";
    case GpsSource::CACHED:
        return "Cache";
    default:
        return "None";
    }
}

const char *gps_selector_source_name()
{
    return source_name_of(gActiveSource);
}

bool gps_selector_get_fix(double &lat, double &lon, float &speedKmh,
                          uint8_t &satellites, float &hdop)
{
    const GpsQuality *src = nullptr;

    switch (gActiveSource)
    {
    case GpsSource::NEO6M:
        src = &gNeo6m;
        break;
    case GpsSource::PHONE:
        src = &gPhone;
        break;
    case GpsSource::CACHED:
        if (gCache.valid && gCache.ageMs() < GPS_CACHE_MAX_AGE_MS)
            src = &gCache;
        break;
    default:
        break;
    }

    if (!src || !src->valid)
        return false;

    lat = src->lat;
    lon = src->lon;
    speedKmh = src->speedKmh;
    satellites = src->satellites;
    hdop = src->hdop;
    return true;
}

int gps_selector_get_score()
{
    if (gActiveSource == GpsSource::NEO6M)
        return score_gps(gNeo6m);
    else if (gActiveSource == GpsSource::PHONE)
        return score_gps(gPhone);
    else if (gActiveSource == GpsSource::CACHED)
        return 0;
    return -1;
}

void gps_selector_print()
{
    uint32_t nowMs = millis();
    int sNeo = score_gps(gNeo6m);
    int sPhone = score_gps(gPhone);

    Serial.printf("[GPS_SEL] ACTIVE=%s | NEO(age=%lums sats=%d hdop=%.1f score=%d) | "
                  "PHONE(age=%lums sats=%d hdop=%.1f score=%d) | switch=%lums ago\n",
                  gps_selector_source_name(),
                  (unsigned long)gNeo6m.ageMs(), gNeo6m.satellites, gNeo6m.hdop, sNeo,
                  (unsigned long)gPhone.ageMs(), gPhone.satellites, gPhone.hdop, sPhone,
                  (unsigned long)(nowMs - gLastSwitchMs));
}

void gps_selector_get_both(GpsQuality &neo, GpsQuality &phone)
{
    neo = gNeo6m;
    phone = gPhone;
}

// =========================
