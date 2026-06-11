#include "ble_emergency_beacon.h"

// =========================
// BIẾN TOÀN CỤC
// =========================

static EmergencyBeaconData gBeacon = {false, 0, 0, 0, 0, false, 0, 0};
static NimBLEAdvertising *gAdv = nullptr;
static bool gAdvStarted = false;

// Gửi heartbeat beacon mỗi 2 giây (cập nhật advertising)
static uint32_t gLastBeaconUpdateMs = 0;
static const uint32_t BEACON_UPDATE_MS = 2000;

// =========================
// KHỞI TẠO
// =========================

void emergency_beacon_init()
{
    gBeacon = {false, 0, 0, 0, 0, false, 0, 0};
    gAdvStarted = false;

    Serial.println("[BEACON] Emergency Beacon san sang");
}

// =========================
// ĐÓNG GÓI DỮ LIỆU VÀO MANUFACTURER DATA
// =========================

// Format manufacturer data (20 bytes):
//   [0-3]   float lat
//   [4-7]   float lon
//   [8-11]  float peakG
//   [12-15] float aiProbability
//   [16]    uint8_t isFall (1=ngã, 0=va chạm)
//   [17]    uint8_t satellites
//   [18-19] uint16_t checksum (sum of bytes 0-17)

static uint16_t calcChecksum(const uint8_t *data, size_t len)
{
    uint16_t sum = 0;
    for (size_t i = 0; i < len; i++)
        sum += data[i];
    return sum;
}

static void packBeaconData(uint8_t *buf, const EmergencyBeaconData &b)
{
    // Pack floats (little-endian)
    memcpy(buf + 0, &b.lat, 4);
    memcpy(buf + 4, &b.lon, 4);
    memcpy(buf + 8, &b.peakG, 4);
    memcpy(buf + 12, &b.aiProbability, 4);
    buf[16] = b.isFall ? 1 : 0;
    buf[17] = b.satellites;

    uint16_t cs = calcChecksum(buf, 18);
    buf[18] = cs & 0xFF;
    buf[19] = (cs >> 8) & 0xFF;
}

// =========================
// BẬT BEACON
// =========================

void emergency_beacon_start(double lat, double lon, float peakG,
                            float aiProbability, bool isFall,
                            uint8_t satellites)
{
    // Dừng beacon cũ nếu có
    if (gAdvStarted)
    {
        emergency_beacon_stop();
    }

    // Lưu dữ liệu
    gBeacon.active = true;
    gBeacon.lat = lat;
    gBeacon.lon = lon;
    gBeacon.peakG = peakG;
    gBeacon.aiProbability = aiProbability;
    gBeacon.isFall = isFall;
    gBeacon.satellites = satellites;
    gBeacon.timestamp = millis();

    // Đóng gói manufacturer data
    uint8_t mfgData[20];
    packBeaconData(mfgData, gBeacon);

    // Tạo advertising
    // Sử dụng NimBLEAdvertising để broadcast
    gAdv = NimBLEDevice::getAdvertising();

    // Đặt tên thiết bị ngắn (hiển thị trên máy scan)
    NimBLEAdvertisementData advData;
    advData.setName("SOS-SmartHelmet");
    advData.setManufacturerData(std::string((char *)mfgData, 20));

    // Thêm service UUID để dễ nhận diện
    NimBLEUUID svcUuid = NimBLEUUID((uint16_t)EMERGENCY_BEACON_SERVICE_UUID);
    advData.setCompleteServices(BLEUUID(svcUuid));

    gAdv->setAdvertisementData(advData);

    // Cấu hình advertising: interval nhanh (100ms) để dễ phát hiện
    gAdv->setMinInterval(160); // 100ms
    gAdv->setMaxInterval(200); // 125ms
    gAdv->setMinPreferred(160);
    gAdv->setMaxPreferred(200);

    gAdv->start();
    gAdvStarted = true;
    gLastBeaconUpdateMs = millis();

    Serial.println("[BEACON] 🆘 BAT DAU PHAT TIN HIEU CAP CUU!");
    Serial.printf("[BEACON] GPS=%.6f,%.6f peak=%.2fg AI=%.2f fall=%d\n",
                  lat, lon, peakG, aiProbability, isFall ? 1 : 0);
}

// =========================
// TẮT BEACON
// =========================

void emergency_beacon_stop()
{
    if (gAdvStarted && gAdv)
    {
        gAdv->stop();
        gAdvStarted = false;
        Serial.println("[BEACON] Da tat tin hieu cap cuu");
    }
    gBeacon.active = false;
}

// =========================
// CẬP NHẬT GPS (khi beacon đang chạy)
// =========================

void emergency_beacon_update_gps(double lat, double lon, uint8_t satellites)
{
    if (!gBeacon.active || !gAdvStarted)
        return;

    gBeacon.lat = lat;
    gBeacon.lon = lon;
    gBeacon.satellites = satellites;
    gBeacon.timestamp = millis();
}

// =========================
// TRẠNG THÁI
// =========================

bool emergency_beacon_is_active()
{
    return gBeacon.active;
}

void emergency_beacon_print()
{
    if (!gBeacon.active)
    {
        Serial.println("[BEACON] Trang thai: OFF");
        return;
    }

    uint32_t ageS = (millis() - gBeacon.timestamp) / 1000;
    Serial.printf("[BEACON] 🆘 DANG PHAT | GPS=%.6f,%.6f peak=%.2fg AI=%.2f "
                  "fall=%d sats=%d age=%lus\n",
                  gBeacon.lat, gBeacon.lon,
                  gBeacon.peakG, gBeacon.aiProbability,
                  gBeacon.isFall ? 1 : 0,
                  gBeacon.satellites,
                  (unsigned long)ageS);
}
