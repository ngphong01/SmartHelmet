#include "wifi_manager.h"
#include <WiFi.h>
#include <Preferences.h>

static WiFiNetwork gNetworks[WIFI_MAX_NETWORKS];
static int gNetworkCount = 0;
static WiFiState gState = WiFiState::DISCONNECTED;
static uint32_t gLastScanMs = 0;
static uint32_t gScanIntervalMs = 30000; // scan mỗi 30s khi chưa kết nối
static uint32_t gLastReconnectAttemptMs = 0;
static uint32_t gReconnectIntervalMs = 15000; // thử lại mỗi 15s
static String gCurrentSSID = "";
static Preferences gPrefs;

static const char *PREFS_NS = "wifi_mgr";

// =========================
// LƯU / ĐỌC NVS
// =========================

static void save_networks_to_nvs()
{
    gPrefs.begin(PREFS_NS, false);
    gPrefs.putInt("count", gNetworkCount);
    for (int i = 0; i < gNetworkCount; i++)
    {
        char key1[32], key2[32], key3[32];
        snprintf(key1, sizeof(key1), "ssid_%d", i);
        snprintf(key2, sizeof(key2), "pass_%d", i);
        snprintf(key3, sizeof(key3), "prio_%d", i);
        gPrefs.putString(key1, gNetworks[i].ssid);
        gPrefs.putString(key2, gNetworks[i].password);
        gPrefs.putInt(key3, gNetworks[i].priority);
    }
    gPrefs.end();
}

static void load_networks_from_nvs()
{
    gPrefs.begin(PREFS_NS, true);
    gNetworkCount = gPrefs.getInt("count", 0);
    if (gNetworkCount > WIFI_MAX_NETWORKS)
        gNetworkCount = WIFI_MAX_NETWORKS;

    for (int i = 0; i < gNetworkCount; i++)
    {
        char key1[32], key2[32], key3[32];
        snprintf(key1, sizeof(key1), "ssid_%d", i);
        snprintf(key2, sizeof(key2), "pass_%d", i);
        snprintf(key3, sizeof(key3), "prio_%d", i);
        String ssid = gPrefs.getString(key1, "");
        String pass = gPrefs.getString(key2, "");
        if (ssid.length() > 0)
        {
            strncpy(gNetworks[i].ssid, ssid.c_str(), 32);
            strncpy(gNetworks[i].password, pass.c_str(), 64);
            gNetworks[i].priority = gPrefs.getInt(key3, 0);
            gNetworks[i].rssi = -999;
        }
    }
    gPrefs.end();

    Serial.printf("[WIFI_MGR] Da nap %d WiFi networks tu NVS\n", gNetworkCount);
}

// =========================
// SCAN & AUTO-CONNECT
// =========================

static int find_best_network()
{
    int bestIdx = -1;
    int bestScore = -9999; // priority thấp + RSSI cao = score cao

    for (int i = 0; i < gNetworkCount; i++)
    {
        if (gNetworks[i].rssi > -200)
        { // đã được scan thấy
            // Score = RSSI - priority*2 (ưu tiên RSSI mạnh, priority thấp)
            int score = gNetworks[i].rssi - gNetworks[i].priority * 2;
            if (score > bestScore)
            {
                bestScore = score;
                bestIdx = i;
            }
        }
    }
    return bestIdx;
}

static void scan_networks()
{
    Serial.println("[WIFI_MGR] Bat dau scan WiFi...");
    gState = WiFiState::SCANNING;

    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    delay(100);

    int n = WiFi.scanNetworks(false, true); // async=false, show_hidden=true
    Serial.printf("[WIFI_MGR] Tim thay %d mang WiFi\n", n);

    // Reset RSSI
    for (int i = 0; i < gNetworkCount; i++)
    {
        gNetworks[i].rssi = -999;
    }

    // Map scan results to saved networks
    for (int i = 0; i < n; i++)
    {
        String scannedSSID = WiFi.SSID(i);
        int scannedRSSI = WiFi.RSSI(i);

        for (int j = 0; j < gNetworkCount; j++)
        {
            if (scannedSSID.equals(gNetworks[j].ssid))
            {
                if (scannedRSSI > gNetworks[j].rssi)
                {
                    gNetworks[j].rssi = scannedRSSI;
                }
                Serial.printf("  [MATCH] %s RSSI=%d (da luu)\n",
                              gNetworks[j].ssid, scannedRSSI);
                break;
            }
        }
    }

    // Dọn dẹp kết quả scan
    WiFi.scanDelete();
}

static bool connect_to(int networkIdx)
{
    if (networkIdx < 0 || networkIdx >= gNetworkCount)
        return false;

    WiFiNetwork &net = gNetworks[networkIdx];
    gState = WiFiState::CONNECTING;
    gCurrentSSID = net.ssid;

    Serial.printf("[WIFI_MGR] Dang ket noi %s ...\n", net.ssid);
    WiFi.mode(WIFI_STA);
    WiFi.begin(net.ssid, net.password);

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30)
    { // 15s timeout
        delay(500);
        Serial.print(".");
        attempts++;
    }

    if (WiFi.status() == WL_CONNECTED)
    {
        Serial.println();
        Serial.printf("[WIFI_MGR][OK] Da ket noi %s, IP: %s, RSSI: %d\n",
                      net.ssid, WiFi.localIP().toString().c_str(), WiFi.RSSI());
        gState = WiFiState::CONNECTED;
        return true;
    }

    Serial.println();
    Serial.printf("[WIFI_MGR][LOI] Khong the ket noi %s\n", net.ssid);
    gState = WiFiState::DISCONNECTED;
    gCurrentSSID = "";
    return false;
}

// =========================
// API PUBLIC
// =========================

void wifi_manager_init()
{
    memset(gNetworks, 0, sizeof(gNetworks));
    gNetworkCount = 0;
    gState = WiFiState::DISCONNECTED;
    gLastScanMs = 0;
    gCurrentSSID = "";

    // Nạp networks từ NVS
    load_networks_from_nvs();

    // Thêm WiFi mặc định từ secrets.h nếu chưa có
    // (sẽ được thêm trong main.cpp sau khi include secrets.h)

    WiFi.mode(WIFI_STA);
    Serial.println("[WIFI_MGR] Khoi tao xong");
}

bool wifi_manager_add_network(const char *ssid, const char *password, int8_t priority)
{
    if (!ssid || strlen(ssid) == 0)
        return false;
    if (gNetworkCount >= WIFI_MAX_NETWORKS)
    {
        Serial.println("[WIFI_MGR][LOI] Danh sach WiFi day!");
        return false;
    }

    // Kiểm tra trùng
    for (int i = 0; i < gNetworkCount; i++)
    {
        if (strcmp(gNetworks[i].ssid, ssid) == 0)
        {
            // Cập nhật password/priority
            strncpy(gNetworks[i].password, password ? password : "", 64);
            gNetworks[i].priority = priority;
            save_networks_to_nvs();
            Serial.printf("[WIFI_MGR] Cap nhat WiFi: %s (prio=%d)\n", ssid, priority);
            return true;
        }
    }

    // Thêm mới
    strncpy(gNetworks[gNetworkCount].ssid, ssid, 32);
    strncpy(gNetworks[gNetworkCount].password, password ? password : "", 64);
    gNetworks[gNetworkCount].priority = priority;
    gNetworks[gNetworkCount].rssi = -999;
    gNetworkCount++;

    save_networks_to_nvs();
    Serial.printf("[WIFI_MGR] Them WiFi: %s (prio=%d, total=%d)\n",
                  ssid, priority, gNetworkCount);
    return true;
}

bool wifi_manager_remove_network(const char *ssid)
{
    for (int i = 0; i < gNetworkCount; i++)
    {
        if (strcmp(gNetworks[i].ssid, ssid) == 0)
        {
            // Dịch các phần tử còn lại
            for (int j = i; j < gNetworkCount - 1; j++)
            {
                gNetworks[j] = gNetworks[j + 1];
            }
            gNetworkCount--;
            save_networks_to_nvs();
            Serial.printf("[WIFI_MGR] Da xoa WiFi: %s\n", ssid);
            return true;
        }
    }
    return false;
}

void wifi_manager_loop()
{
    uint32_t now = millis();

    switch (gState)
    {
    case WiFiState::DISCONNECTED:
        // Scan định kỳ khi chưa kết nối
        if (gNetworkCount > 0 && (now - gLastScanMs >= gScanIntervalMs))
        {
            gLastScanMs = now;
            scan_networks();

            int best = find_best_network();
            if (best >= 0)
            {
                connect_to(best);
            }
        }

        // Thử reconnect
        if (gNetworkCount > 0 && (now - gLastReconnectAttemptMs >= gReconnectIntervalMs))
        {
            gLastReconnectAttemptMs = now;
            int best = find_best_network();
            if (best >= 0)
            {
                connect_to(best);
            }
            else
            {
                // Scan nếu chưa có kết quả
                scan_networks();
                best = find_best_network();
                if (best >= 0)
                {
                    connect_to(best);
                }
            }
        }
        break;

    case WiFiState::CONNECTED:
        // Kiểm tra kết nối còn sống
        if (WiFi.status() != WL_CONNECTED)
        {
            Serial.printf("[WIFI_MGR] Mat ket noi %s\n", gCurrentSSID.c_str());
            gState = WiFiState::DISCONNECTED;
            gCurrentSSID = "";
            gLastReconnectAttemptMs = now;
        }
        break;

    default:
        break;
    }
}

bool wifi_manager_connect_now()
{
    if (gNetworkCount == 0)
    {
        Serial.println("[WIFI_MGR] Khong co network nao duoc luu");
        return false;
    }

    scan_networks();
    int best = find_best_network();
    if (best >= 0)
    {
        return connect_to(best);
    }
    return false;
}

void wifi_manager_disconnect()
{
    WiFi.disconnect(true);
    gState = WiFiState::DISCONNECTED;
    gCurrentSSID = "";
    Serial.println("[WIFI_MGR] Da ngat ket noi WiFi");
}

WiFiState wifi_manager_get_state() { return gState; }

bool wifi_manager_is_connected()
{
    return gState == WiFiState::CONNECTED && WiFi.status() == WL_CONNECTED;
}

String wifi_manager_get_ip()
{
    if (wifi_manager_is_connected())
    {
        return WiFi.localIP().toString();
    }
    return "0.0.0.0";
}

int wifi_manager_get_rssi()
{
    if (wifi_manager_is_connected())
    {
        return WiFi.RSSI();
    }
    return -999;
}

void wifi_manager_print_networks()
{
    Serial.println("===== WIFI NETWORKS DA LUU =====");
    for (int i = 0; i < gNetworkCount; i++)
    {
        Serial.printf("  [%d] %s (prio=%d, last_rssi=%d)\n",
                      i, gNetworks[i].ssid, gNetworks[i].priority, gNetworks[i].rssi);
    }
    Serial.printf("  State: %d, Connected: %s\n",
                  (int)gState, gCurrentSSID.length() > 0 ? gCurrentSSID.c_str() : "none");
}

int wifi_manager_network_count() { return gNetworkCount; }

void wifi_manager_set_scan_interval(uint32_t intervalMs)
{
    gScanIntervalMs = intervalMs;
}
