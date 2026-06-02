#include "impact_buffer.h"
#include <Preferences.h>

// Dùng ESP32 Preferences (NVS) để lưu buffer bền vững qua reset
static Preferences gPrefs;
static ImpactEvent gBuffer[IMPACT_BUFFER_MAX];
static int gBufferCount = 0;
static int gPendingBleIdx = 0;  // index đang retry BLE
static int gPendingWifiIdx = 0; // index đang retry WiFi
static uint32_t gLastRetryMs = 0;

static const char *PREFS_NAMESPACE = "impact_buf";

// =========================
// LƯU / ĐỌC NVS
// =========================

static void save_buffer_to_nvs()
{
    gPrefs.begin(PREFS_NAMESPACE, false);
    gPrefs.putInt("count", gBufferCount);
    gPrefs.putInt("ble_idx", gPendingBleIdx);
    gPrefs.putInt("wifi_idx", gPendingWifiIdx);

    // Lưu từng sự kiện dưới dạng blob
    for (int i = 0; i < gBufferCount; i++)
    {
        char key[32];
        snprintf(key, sizeof(key), "evt_%d", i);
        gPrefs.putBytes(key, &gBuffer[i], sizeof(ImpactEvent));
    }
    gPrefs.end();
}

static void load_buffer_from_nvs()
{
    gPrefs.begin(PREFS_NAMESPACE, true);
    gBufferCount = gPrefs.getInt("count", 0);
    gPendingBleIdx = gPrefs.getInt("ble_idx", 0);
    gPendingWifiIdx = gPrefs.getInt("wifi_idx", 0);

    if (gBufferCount > IMPACT_BUFFER_MAX)
        gBufferCount = IMPACT_BUFFER_MAX;

    for (int i = 0; i < gBufferCount; i++)
    {
        char key[32];
        snprintf(key, sizeof(key), "evt_%d", i);
        size_t len = gPrefs.getBytesLength(key);
        if (len == sizeof(ImpactEvent))
        {
            gPrefs.getBytes(key, &gBuffer[i], sizeof(ImpactEvent));
        }
    }
    gPrefs.end();

    Serial.printf("[IMPACT_BUF] Da nap %d su kien tu NVS (ble_idx=%d, wifi_idx=%d)\n",
                  gBufferCount, gPendingBleIdx, gPendingWifiIdx);
}

// =========================
// KHỞI TẠO
// =========================

void impact_buffer_init()
{
    memset(gBuffer, 0, sizeof(gBuffer));
    gBufferCount = 0;
    gPendingBleIdx = 0;
    gPendingWifiIdx = 0;
    gLastRetryMs = 0;

    load_buffer_from_nvs();
}

// =========================
// PUSH SỰ KIỆN MỚI
// =========================

bool impact_buffer_push(float lat, float lon, float speedKmh,
                        float aiProbability, float peakG, bool gpsValid)
{
    // Dọn dẹp các sự kiện đã gửi xong trước khi thêm mới
    impact_buffer_cleanup();

    if (gBufferCount >= IMPACT_BUFFER_MAX)
    {
        Serial.println("[IMPACT_BUF][LOI] Buffer day! Ghi de su kien cu nhat.");
        // Dịch buffer sang trái, ghi đè sự kiện cũ nhất
        for (int i = 0; i < IMPACT_BUFFER_MAX - 1; i++)
        {
            gBuffer[i] = gBuffer[i + 1];
        }
        gBufferCount = IMPACT_BUFFER_MAX - 1;
    }

    ImpactEvent &evt = gBuffer[gBufferCount];
    evt.timestamp = millis();
    evt.lat = lat;
    evt.lon = lon;
    evt.speedKmh = speedKmh;
    evt.aiProbability = aiProbability;
    evt.peakG = peakG;
    evt.gpsValid = gpsValid;
    evt.sentViaBle = false;
    evt.sentViaWifi = false;
    evt.retryCount = 0;

    gBufferCount++;
    save_buffer_to_nvs();

    Serial.printf("[IMPACT_BUF] Da luu su kien #%d (total=%d): p=%.2f, peak=%.2fg, gps=%d\n",
                  gBufferCount - 1, gBufferCount, aiProbability, peakG, gpsValid ? 1 : 0);
    return true;
}

// =========================
// RETRY LOGIC
// =========================

const ImpactEvent *impact_buffer_get_pending_ble()
{
    if (gBufferCount == 0)
        return nullptr;

    // Kiểm tra giới hạn retry duration cho sự kiện hiện tại
    if (gPendingBleIdx < gBufferCount)
    {
        ImpactEvent &evt = gBuffer[gPendingBleIdx];
        if (evt.sentViaBle)
        {
            // Đã gửi rồi, chuyển sang sự kiện tiếp
            gPendingBleIdx++;
            save_buffer_to_nvs();
            return impact_buffer_get_pending_ble();
        }

        uint32_t ageMs = millis() - evt.timestamp;
        if (ageMs > IMPACT_RETRY_DURATION_MS)
        {
            Serial.printf("[IMPACT_BUF] Su kien #%d da qua han retry (%lums), bo qua\n",
                          gPendingBleIdx, (unsigned long)ageMs);
            evt.sentViaBle = true; // đánh dấu đã xử lý để không retry nữa
            gPendingBleIdx++;
            save_buffer_to_nvs();
            return impact_buffer_get_pending_ble();
        }

        return &evt;
    }

    return nullptr;
}

void impact_buffer_mark_ble_sent()
{
    if (gPendingBleIdx < gBufferCount)
    {
        gBuffer[gPendingBleIdx].sentViaBle = true;
        gBuffer[gPendingBleIdx].retryCount++;
        Serial.printf("[IMPACT_BUF] Da gui BLE thanh cong su kien #%d\n", gPendingBleIdx);
        gPendingBleIdx++;
        save_buffer_to_nvs();
    }
}

const ImpactEvent *impact_buffer_get_pending_wifi()
{
    if (gBufferCount == 0)
        return nullptr;

    if (gPendingWifiIdx < gBufferCount)
    {
        ImpactEvent &evt = gBuffer[gPendingWifiIdx];
        if (evt.sentViaWifi)
        {
            gPendingWifiIdx++;
            save_buffer_to_nvs();
            return impact_buffer_get_pending_wifi();
        }

        uint32_t ageMs = millis() - evt.timestamp;
        if (ageMs > IMPACT_RETRY_DURATION_MS)
        {
            evt.sentViaWifi = true;
            gPendingWifiIdx++;
            save_buffer_to_nvs();
            return impact_buffer_get_pending_wifi();
        }

        return &evt;
    }

    return nullptr;
}

void impact_buffer_mark_wifi_sent()
{
    if (gPendingWifiIdx < gBufferCount)
    {
        gBuffer[gPendingWifiIdx].sentViaWifi = true;
        Serial.printf("[IMPACT_BUF] Da gui WiFi thanh cong su kien #%d\n", gPendingWifiIdx);
        gPendingWifiIdx++;
        save_buffer_to_nvs();
    }
}

// =========================
// TIỆN ÍCH
// =========================

bool impact_buffer_has_pending()
{
    for (int i = 0; i < gBufferCount; i++)
    {
        if (!gBuffer[i].sentViaBle || !gBuffer[i].sentViaWifi)
        {
            return true;
        }
    }
    return false;
}

int impact_buffer_pending_count()
{
    int count = 0;
    for (int i = 0; i < gBufferCount; i++)
    {
        if (!gBuffer[i].sentViaBle || !gBuffer[i].sentViaWifi)
        {
            count++;
        }
    }
    return count;
}

void impact_buffer_print_status()
{
    Serial.printf("[IMPACT_BUF] Tong: %d su kien, Cho BLE: %d, Cho WiFi: %d\n",
                  gBufferCount,
                  gBufferCount - gPendingBleIdx,
                  gBufferCount - gPendingWifiIdx);
    for (int i = 0; i < gBufferCount; i++)
    {
        ImpactEvent &e = gBuffer[i];
        uint32_t age = millis() - e.timestamp;
        Serial.printf("  #%d: age=%lu s, p=%.2f, g=%.2f, BLE=%d, WiFi=%d, retry=%d\n",
                      i, (unsigned long)(age / 1000), e.aiProbability, e.peakG,
                      e.sentViaBle ? 1 : 0, e.sentViaWifi ? 1 : 0, e.retryCount);
    }
}

void impact_buffer_cleanup()
{
    // Xóa các sự kiện đã gửi xong cả BLE lẫn WiFi
    int writeIdx = 0;
    for (int i = 0; i < gBufferCount; i++)
    {
        if (gBuffer[i].sentViaBle && gBuffer[i].sentViaWifi)
        {
            // Bỏ qua - đã xong
        }
        else
        {
            if (writeIdx != i)
            {
                gBuffer[writeIdx] = gBuffer[i];
            }
            writeIdx++;
        }
    }

    int removed = gBufferCount - writeIdx;
    if (removed > 0)
    {
        gBufferCount = writeIdx;
        // Reset index
        if (gPendingBleIdx > gBufferCount)
            gPendingBleIdx = gBufferCount;
        if (gPendingWifiIdx > gBufferCount)
            gPendingWifiIdx = gBufferCount;
        save_buffer_to_nvs();
        Serial.printf("[IMPACT_BUF] Da don dep %d su kien da xu ly\n", removed);
    }
}
