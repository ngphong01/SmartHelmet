#include "ble_mesh.h"
#include <NimBLEDevice.h>

// =========================
// BIẾN TOÀN CỤC
// =========================

static bool gBroadcasting = false;
static uint32_t gBroadcastStartMs = 0;
static uint32_t gBroadcastDurationMs = 120000; // broadcast 2 phút
static uint32_t gBroadcastIntervalMs = 200;    // mỗi 200ms
static uint32_t gLastBroadcastMs = 0;
static uint32_t gLastScanMs = 0;
static uint32_t gScanIntervalMs = 1000; // scan mỗi 1s

static ImpactBeaconData gCurrentBeacon;
static ImpactBeaconCallback gBeaconCallback = nullptr;
static NimBLEScan *gMeshScan = nullptr;

// Số beacon phát hiện gần đây
static uint32_t gBeaconsDetected = 0;
static uint32_t gLastBeaconDetectedMs = 0;

// =========================
// IMPLEMENTATION
// =========================

// Tạo manufacturer data cho impact beacon
// Format: [UUID 2 bytes] [ImpactBeaconData 24 bytes]
static void build_beacon_payload(uint8_t *out, size_t *outLen, const ImpactBeaconData &data)
{
    // Dùng Manufacturer Specific Data (AD Type 0xFF)
    // Company ID = 0xFFFF (dùng cho testing)
    out[0] = 0xFF; // Manufacturer Specific Data
    out[1] = 26;   // length: 2 byte company + 24 byte data
    out[2] = 0xFF; // Company ID low
    out[3] = 0xFF; // Company ID high

    // Copy ImpactBeaconData (24 bytes)
    memcpy(out + 4, &data, sizeof(ImpactBeaconData));
    *outLen = 4 + sizeof(ImpactBeaconData); // 28 bytes
}

// =========================
// KHỞI TẠO
// =========================

void ble_mesh_init()
{
    gBroadcasting = false;
    gBeaconsDetected = 0;
    gLastBeaconDetectedMs = 0;
    memset(&gCurrentBeacon, 0, sizeof(gCurrentBeacon));

    // Dùng NimBLEScan để quét beacon từ mũ khác
    gMeshScan = NimBLEDevice::getScan();
    if (gMeshScan)
    {
        gMeshScan->setActiveScan(true);
        gMeshScan->setInterval(100); // 62.5ms
        gMeshScan->setWindow(50);    // 31.25ms
    }

    Serial.println("[BLE_MESH] Khoi tao xong - san sang broadcast/quét impact beacon");
}

// =========================
// BROADCAST
// =========================

void ble_mesh_broadcast_impact(float lat, float lon, float peakG,
                               float aiProb, bool gpsValid, bool isSos)
{
    gCurrentBeacon.version = 1;
    gCurrentBeacon.flags = 0;
    if (true)
        gCurrentBeacon.flags |= 0x01; // bit0 = impact
    if (gpsValid)
        gCurrentBeacon.flags |= 0x02; // bit1 = gps valid
    if (isSos)
        gCurrentBeacon.flags |= 0x04; // bit2 = SOS
    gCurrentBeacon.timestamp = millis();
    gCurrentBeacon.lat = lat;
    gCurrentBeacon.lon = lon;
    gCurrentBeacon.peakG = peakG;
    gCurrentBeacon.aiProb = aiProb;
    gCurrentBeacon.helmetId = 0x0001; // H001

    gBroadcasting = true;
    gBroadcastStartMs = millis();
    gLastBroadcastMs = 0; // gửi ngay lập tức

    Serial.printf("[BLE_MESH] Bat dau broadcast impact beacon: p=%.2f, g=%.2f, gps=%d\n",
                  aiProb, peakG, gpsValid ? 1 : 0);
}

void ble_mesh_stop_broadcast()
{
    gBroadcasting = false;
    Serial.println("[BLE_MESH] Dung broadcast impact beacon");
}

static void do_broadcast()
{
    if (!gBroadcasting)
        return;

    uint32_t now = millis();

    // Kiểm tra thời gian broadcast
    if (now - gBroadcastStartMs > gBroadcastDurationMs)
    {
        Serial.println("[BLE_MESH] Het thoi gian broadcast (2 phut)");
        gBroadcasting = false;
        return;
    }

    // Gửi beacon định kỳ
    if (now - gLastBroadcastMs >= gBroadcastIntervalMs)
    {
        gLastBroadcastMs = now;

        // Dùng Manufacturer Specific Data trong Scan Response
        // Cập nhật dữ liệu beacon
        gCurrentBeacon.timestamp = millis(); // cập nhật timestamp mới nhất

        uint8_t payload[31];
        size_t payloadLen = 0;
        build_beacon_payload(payload, &payloadLen, gCurrentBeacon);

        // Cập nhật manufacturer data vào advertisement hiện tại
        NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
        if (adv)
        {
            NimBLEAdvertisementData scanResp;
            scanResp.setManufacturerData(std::string((char *)payload, payloadLen));
            adv->setScanResponseData(scanResp);
            // Không cần restart advertising - scan response tự động được gửi khi có scan request
        }
    }
}

// =========================
// SCAN (nhận beacon từ mũ khác)
// =========================

void ble_mesh_scan_loop()
{
    // Broadcast nếu đang active
    do_broadcast();

    uint32_t now = millis();

    // Scan định kỳ
    if (now - gLastScanMs < gScanIntervalMs)
        return;
    gLastScanMs = now;

    if (!gMeshScan)
        return;

    NimBLEScanResults results = gMeshScan->getResults();
    int count = results.getCount();

    for (int i = 0; i < count; i++)
    {
        NimBLEAdvertisedDevice dev = results.getDevice(i);

        // Kiểm tra manufacturer data
        std::string mfgData = dev.getManufacturerData();
        if (mfgData.length() < sizeof(ImpactBeaconData) + 2)
            continue;

        // Kiểm tra Company ID = 0xFFFF
        if (mfgData.length() < 4)
            continue;
        uint16_t companyId = ((uint8_t)mfgData[0]) | (((uint8_t)mfgData[1]) << 8);
        if (companyId != 0xFFFF)
            continue;

        // Parse ImpactBeaconData
        ImpactBeaconData beacon;
        if (mfgData.length() >= 2 + sizeof(ImpactBeaconData))
        {
            memcpy(&beacon, mfgData.data() + 2, sizeof(ImpactBeaconData));

            if (beacon.version == 1 && (beacon.flags & 0x01))
            {
                gBeaconsDetected++;
                gLastBeaconDetectedMs = now;

                int rssi = dev.getRSSI();
                Serial.printf("[BLE_MESH][RELAY] Phat hien beacon tu mu #%d: p=%.2f, g=%.2f, RSSI=%d\n",
                              beacon.helmetId, beacon.aiProb, beacon.peakG, rssi);

                // Gọi callback nếu có
                if (gBeaconCallback)
                {
                    gBeaconCallback(beacon, rssi);
                }
            }
        }
    }
}

// =========================
// CALLBACK
// =========================

void ble_mesh_on_beacon_detected(ImpactBeaconCallback cb)
{
    gBeaconCallback = cb;
}

// =========================
// STATUS
// =========================

bool ble_mesh_is_broadcasting()
{
    return gBroadcasting;
}

void ble_mesh_print_status()
{
    Serial.println("===== BLE MESH STATUS =====");
    Serial.printf("  Broadcasting: %s\n", gBroadcasting ? "YES" : "NO");
    if (gBroadcasting)
    {
        uint32_t elapsed = millis() - gBroadcastStartMs;
        Serial.printf("  Elapsed: %lu ms / %lu ms\n",
                      (unsigned long)elapsed, (unsigned long)gBroadcastDurationMs);
    }
    Serial.printf("  Beacons detected: %lu\n", (unsigned long)gBeaconsDetected);
    Serial.printf("  Last beacon: %lu ms ago\n",
                  (unsigned long)(millis() - gLastBeaconDetectedMs));
}
