#include "log_system.h"
#include <esp_mac.h>

// ============================================================
// GLOBAL LOG LEVEL
// ============================================================
LogLevel gLogLevel = LVL_INFO;

// ============================================================
// RESET REASON
// ============================================================
const char *getResetReasonStr()
{
    switch (esp_reset_reason())
    {
    case ESP_RST_POWERON:
        return "POWERON";
    case ESP_RST_SW:
        return "SW_RESET";
    case ESP_RST_PANIC:
        return "PANIC (crash!)";
    case ESP_RST_INT_WDT:
        return "INT_WDT";
    case ESP_RST_TASK_WDT:
        return "TASK_WDT";
    case ESP_RST_WDT:
        return "WDT";
    case ESP_RST_DEEPSLEEP:
        return "DEEPSLEEP";
    case ESP_RST_BROWNOUT:
        return "BROWNOUT (sut ap!)";
    case ESP_RST_SDIO:
        return "SDIO";
    default:
        return "UNKNOWN";
    }
}

// ============================================================
// BOOT INFO
// ============================================================
void printBootInfo()
{
    // Đợi Serial sẵn sàng
    delay(50);

    LOG_RAW("\n");
    LOG_RAW("============================================================\n");
    LOG_RAW("    MU BAO HIEM THONG MINH - SmartHelmet Firmware\n");
    LOG_RAW("    Build: %s %s\n", __DATE__, __TIME__);

    // Chip info
    esp_chip_info_t chipInfo;
    esp_chip_info(&chipInfo);
    LOG_RAW("    Chip: %s rev %d, %d MHz, %d cores\n",
            "ESP32",
            chipInfo.revision,
            ESP.getCpuFreqMHz(),
            chipInfo.cores);

    // Flash info
    LOG_RAW("    Flash: %d MB (%s)\n",
            ESP.getFlashChipSize() / 1048576,
            chipInfo.features & CHIP_FEATURE_EMB_FLASH ? "internal" : "external");

    // MAC
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    LOG_RAW("    MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
            mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    LOG_RAW("    Reset reason: %s\n", getResetReasonStr());
    LOG_RAW("    Free heap: %d KB\n", ESP.getFreeHeap() / 1024);
    LOG_RAW("============================================================\n\n");
}

// ============================================================
// CONFIG INFO
// ============================================================
void printConfigInfo()
{
    LOG_INFO("CONFIG", "Sample rate: 1000 Hz, FFT size: 512, Overlap: 50%%");
    LOG_INFO("CONFIG", "Impact: p>0.85, peak_g>2.0g, confirm=1 window, debounce=5s");
    LOG_INFO("CONFIG", "Fall: tilt>55 deg, gyro>120 dps, hold=1.5s");
    LOG_INFO("CONFIG", "Ride: auto-detect >8 km/h, idle timeout=300s");
    LOG_INFO("CONFIG", "BLE: 2 phones max, heartbeat 5s, MTU 185");
    LOG_INFO("CONFIG", "WiFi: multi-SSID, auto-scan 30s");
    LOG_INFO("CONFIG", "Log level: %d (0=ERR 1=WARN 2=INFO 3=DEBUG)", (int)gLogLevel);
}

// ============================================================
// STATS SUMMARY
// ============================================================
void printStatsSummary(uint32_t uptimeS, uint32_t freeHeap,
                       bool wifiConnected, const char *wifiSsid,
                       int bleConnCount, bool gpsValid,
                       uint8_t sats, float lat, float lon,
                       float peakGMax, float aiPMax,
                       const char *rideState, float speedKmh,
                       uint32_t impactCount, uint32_t fallCount,
                       uint32_t sosCount, uint32_t falsePosCount)
{
    unsigned long now = millis();
    LOG_RAW("\n[%08lu][STATS] ======= He thong (%lu s) =======\n", now, (unsigned long)uptimeS);
    LOG_RAW("[%08lu][STATS] Heap: %lu KB free | Log: %s\n",
            now, (unsigned long)(freeHeap / 1024),
            gLogLevel == LVL_DEBUG ? "DEBUG" : gLogLevel == LVL_INFO ? "INFO"
                                           : gLogLevel == LVL_WARN   ? "WARN"
                                                                     : "ERROR");

    // WiFi
    if (wifiConnected)
    {
        LOG_RAW("[%08lu][STATS] WiFi: %s (%d dBm) | Telegram: san sang\n",
                now, wifiSsid, WiFi.RSSI());
    }
    else
    {
        LOG_RAW("[%08lu][STATS] WiFi: disconnected | Telegram: chua san sang\n", now);
    }

    // BLE
    LOG_RAW("[%08lu][STATS] BLE: %d/2 phone | %s\n", now, bleConnCount,
            bleConnCount > 0 ? "streaming" : "advertising...");

    // GPS
    if (gpsValid)
    {
        LOG_RAW("[%08lu][STATS] GPS: lat=%.6f lon=%.6f | sats=%d | speed=%.1f km/h\n",
                now, lat, lon, sats, speedKmh);
    }
    else
    {
        LOG_RAW("[%08lu][STATS] GPS: NO_FIX | sats=%d\n", now, sats);
    }

    // IMU + AI
    LOG_RAW("[%08lu][STATS] IMU: 1000 Hz | peak_g_max=%.2f | ai_p_max=%.3f\n",
            now, peakGMax, aiPMax);

    // Ride state
    LOG_RAW("[%08lu][STATS] Ride: %s | speed=%.1f km/h\n", now, rideState, speedKmh);

    // Events
    LOG_RAW("[%08lu][STATS] Events: impact=%lu fall=%lu sos=%lu false_pos=%lu\n",
            now, (unsigned long)impactCount, (unsigned long)fallCount,
            (unsigned long)sosCount, (unsigned long)falsePosCount);

    LOG_RAW("[%08lu][STATS] =========================================\n\n", now);
}
