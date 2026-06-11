#include "ble_manager.h"
#include "gps_cache.h"
#include "gps_selector.h"

// =========================
// UUID - Nordic UART Service
// =========================
static const char *UART_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
static const char *UART_CHAR_RX_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
static const char *UART_CHAR_TX_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

// =========================
// BIẾN TOÀN CỤC
// =========================

static NimBLEServer *gServer = nullptr;
static NimBLECharacteristic *gNotifyChars[BLE_MAX_CONNECTIONS] = {nullptr};
static NimBLECharacteristic *gHeartbeatNotifyChar = nullptr;
static NimBLECharacteristic *gHeartbeatWriteChar = nullptr;

static BlePhoneInfo gPhones[BLE_MAX_CONNECTIONS];
static BleConnectionStats gStats = {};

// Trạng thái điều khiển từ app
static bool gBleStreamOn = false;
static volatile bool gBleAck = false;
static volatile bool gBleSos = false;
static volatile bool gBleTestImpact = false;

static uint32_t gLastHeartbeatSendMs = 0;
static uint32_t gLastAdvRestartMs = 0;

// =========================
// CALLBACK: UART RX (lệnh từ app)
// =========================

class UartRxCallback : public NimBLECharacteristicCallbacks
{
    int _phoneIndex;

public:
    UartRxCallback(int idx) : _phoneIndex(idx) {}

    void onWrite(NimBLECharacteristic *c) override
    {
        std::string v = c->getValue();

        Serial.printf("[BLE][NHAN][Phone%d] Lenh: %s\n", _phoneIndex, v.c_str());

        if (v == "START")
        {
            gBleStreamOn = true;
            Serial.println("[BLE][RUN] Bat dau stream du lieu");
        }
        else if (v == "STOP")
        {
            gBleStreamOn = false;
            Serial.println("[BLE][STOP] Dung stream du lieu");
        }
        else if (v == "ACK")
        {
            gBleAck = true;
            Serial.println("[BLE][OK] App xac nhan nguoi dung an toan");
        }
        else if (v == "SOS")
        {
            gBleSos = true;
            Serial.println("[BLE][SOS] App gui yeu cau cuu ho");
        }
        else if (v == "TEST_IMPACT")
        {
            gBleTestImpact = true;
            Serial.println("[BLE][TEST] Kich hoat va cham gia lap!");
        }
        else if (v.rfind("GPS:", 0) == 0)
        {
            // Nhận GPS từ điện thoại: "GPS:lat,lon,speedKmh,sats"
            // VD: "GPS:10.762622,106.660172,25.5,12"
            float lat = 0, lon = 0, speed = 0;
            int sats = 0;
            if (sscanf(v.c_str(), "GPS:%f,%f,%f,%d", &lat, &lon, &speed, &sats) >= 2)
            {
                gps_cache_update((double)lat, (double)lon, speed, 1.0f, (uint8_t)sats);
                // Cập nhật GPS Selector → để luân phiên NEO-6M / Phone
                // Phone GPS accuracy ước tính từ số vệ tinh: nhiều vệ tinh → accuracy tốt
                float accuracyEst = (sats >= 12) ? 3.0f : (sats >= 8) ? 5.0f : (sats >= 5) ? 10.0f : 20.0f;
                gps_selector_update_phone((double)lat, (double)lon, speed, (uint8_t)sats, accuracyEst);
                Serial.printf("[BLE][GPS] Nhan GPS tu phone: lat=%.6f lon=%.6f speed=%.1f sats=%d (→ selector)\n",
                              lat, lon, speed, sats);
            }
        }
        else if (v == "PONG")
        {
            // Heartbeat response từ phone - cập nhật lastHeartbeat cho phone đang kết nối
            for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
            {
                if (gPhones[i].state >= BLE_CONNECTED)
                {
                    gPhones[i].lastHeartbeatMs = millis();
                    gPhones[i].state = BLE_HEARTBEAT_OK;
                    gPhones[i].heartbeatTimeoutLogged = false;
                }
            }
        }
    }
};

// =========================
// CALLBACK: Heartbeat Write
// =========================

class HeartbeatRxCallback : public NimBLECharacteristicCallbacks
{
    void onWrite(NimBLECharacteristic *c) override
    {
        std::string v = c->getValue();
        if (v == "PONG")
        {
            for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
            {
                if (gPhones[i].state >= BLE_CONNECTED)
                {
                    gPhones[i].lastHeartbeatMs = millis();
                    gPhones[i].state = BLE_HEARTBEAT_OK;
                    gPhones[i].heartbeatTimeoutLogged = false;
                }
            }
        }
    }
};

// =========================
// CALLBACK: Server (connect/disconnect)
// =========================

class ServerCallbacks : public NimBLEServerCallbacks
{
    void onConnect(NimBLEServer *s, ble_gap_conn_desc *desc) override
    {
        uint16_t handle = desc->conn_handle;

        // Tìm slot trống
        for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
        {
            if (gPhones[i].state == BLE_DISCONNECTED)
            {
                gPhones[i].connHandle = handle;
                gPhones[i].state = BLE_CONNECTED;
                gPhones[i].connectedSinceMs = millis();
                gPhones[i].lastHeartbeatMs = millis();
                gPhones[i].isPrimary = (gStats.totalReconnects == 0 && i == 0);
                gPhones[i].heartbeatTimeoutLogged = false;
                gStats.totalReconnects++;
                gStats.lastDisconnectMs = 0;

                Serial.printf("[BLE][CONNECT][Phone%d] handle=%d, primary=%d, total_conn=%d\n",
                              i, handle, gPhones[i].isPrimary ? 1 : 0,
                              ble_manager_connected_count());
                return;
            }
        }

        // Không còn slot → từ chối kết nối mới
        Serial.println("[BLE][FULL] Da du 2 ket noi, tu choi them");
    }

    // NimBLE >= 1.4: onDisconnect với desc
    void onDisconnect(NimBLEServer *s, ble_gap_conn_desc *desc) override
    {
        uint16_t handle = desc->conn_handle;

        for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
        {
            if (gPhones[i].connHandle == handle)
            {
                uint32_t uptime = (millis() - gPhones[i].connectedSinceMs) / 1000;
                Serial.printf("[BLE][DISCONNECT][Phone%d] handle=%d, uptime=%lu s\n",
                              i, handle, (unsigned long)uptime);

                gPhones[i].state = BLE_DISCONNECTED;
                gPhones[i].connHandle = 0;
                gStats.totalDisconnects++;
                gStats.lastDisconnectMs = millis();
                gStats.uptimeSeconds += uptime;

                NimBLEDevice::startAdvertising();
                gLastAdvRestartMs = millis();
                return;
            }
        }
    }

    // Fallback: onDisconnect không có desc (NimBLE cũ)
    void onDisconnect(NimBLEServer *s) override
    {
        // Dùng getPeerInfo(0) để lấy thông tin peer đầu tiên
        NimBLEConnInfo info = s->getPeerInfo(0);
        uint16_t handle = info.getConnHandle();

        for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
        {
            if (gPhones[i].connHandle == handle)
            {
                uint32_t uptime = (millis() - gPhones[i].connectedSinceMs) / 1000;
                Serial.printf("[BLE][DISCONNECT][Phone%d] handle=%d, uptime=%lu s\n",
                              i, handle, (unsigned long)uptime);

                gPhones[i].state = BLE_DISCONNECTED;
                gPhones[i].connHandle = 0;
                gStats.totalDisconnects++;
                gStats.lastDisconnectMs = millis();
                gStats.uptimeSeconds += uptime;

                NimBLEDevice::startAdvertising();
                gLastAdvRestartMs = millis();
                return;
            }
        }
    }
};

// =========================
// KHỞI TẠO
// =========================

void ble_manager_init()
{
    // Reset trạng thái
    memset(gPhones, 0, sizeof(gPhones));
    memset(&gStats, 0, sizeof(gStats));
    for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
    {
        gPhones[i].state = BLE_DISCONNECTED;
        gNotifyChars[i] = nullptr;
    }

    NimBLEDevice::init("SmartHelmet");
    NimBLEDevice::setMTU(185);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9); // max power

    gServer = NimBLEDevice::createServer();
    gServer->setCallbacks(new ServerCallbacks());

    // ---- UART Service (cho mỗi phone) ----
    NimBLEService *uartSvc = gServer->createService(UART_SERVICE_UUID);

    // TX Characteristic (Notify) - dùng chung cho tất cả phone
    // Mỗi phone sẽ subscribe riêng
    NimBLECharacteristic *pTx = uartSvc->createCharacteristic(
        UART_CHAR_TX_UUID,
        NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ);

    // RX Characteristic (Write) - lệnh từ app
    NimBLECharacteristic *pRx = uartSvc->createCharacteristic(
        UART_CHAR_RX_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
    pRx->setCallbacks(new UartRxCallback(0));

    uartSvc->start();
    gNotifyChars[0] = pTx;

    // ---- Heartbeat Service ----
    NimBLEService *hbSvc = gServer->createService(BLE_HEARTBEAT_SERVICE_UUID);

    gHeartbeatNotifyChar = hbSvc->createCharacteristic(
        BLE_HEARTBEAT_NOTIFY_UUID,
        NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ);

    gHeartbeatWriteChar = hbSvc->createCharacteristic(
        BLE_HEARTBEAT_WRITE_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
    gHeartbeatWriteChar->setCallbacks(new HeartbeatRxCallback());

    hbSvc->start();

    // ---- Advertising ----
    NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(uartSvc->getUUID());
    adv->addServiceUUID(hbSvc->getUUID());
    adv->setScanResponse(true);
    adv->setMinInterval(32); // 20ms
    adv->setMaxInterval(64); // 40ms
    adv->start();

    Serial.println("[OK][BLE_MGR] Dual-phone BLE + Heartbeat da san sang");
    Serial.println("[BLE_MGR] Ten: SmartHelmet, Max connections: 2, Heartbeat: 5s");
}

// =========================
// GỬI DỮ LIỆU
// =========================

// Rate-limit cảnh báo BLE: chỉ in 1 lần khi mất kết nối
static bool gBleWarnedSendBytes = false;
static bool gBleWarnedSendText = false;

bool ble_manager_send_bytes(const uint8_t *data, size_t len)
{
    // Gửi tới tất cả phone đang kết nối
    bool anySent = false;
    for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
    {
        if (gPhones[i].state >= BLE_CONNECTED && gNotifyChars[0])
        {
            gNotifyChars[0]->setValue(data, len);
            gNotifyChars[0]->notify();
            anySent = true;
        }
    }

    if (!anySent)
    {
        if (!gBleWarnedSendBytes)
        {
            Serial.println("[BLE][WARN] Khong co phone nao ket noi de gui du lieu!");
            gBleWarnedSendBytes = true;
        }
    }
    else
    {
        gBleWarnedSendBytes = false; // Reset khi có phone kết nối lại
    }
    return anySent;
}

bool ble_manager_send_text(const char *s)
{
    if (!s || strlen(s) == 0)
        return false;

    // Kiểm tra có phone nào kết nối không
    if (!ble_manager_is_any_connected())
    {
        if (!gBleWarnedSendText)
        {
            Serial.println("[BLE][WARN] Khong the gui text - tat ca phone deu mat ket noi");
            gBleWarnedSendText = true;
        }
        return false;
    }

    size_t len = strlen(s);
    const size_t CHUNK = 180;

    // Gửi từng chunk qua notify
    bool anySent = false;
    size_t offset = 0;
    while (offset < len)
    {
        size_t chunkLen = (len - offset > CHUNK) ? CHUNK : (len - offset);

        for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
        {
            if (gPhones[i].state >= BLE_CONNECTED && gNotifyChars[0])
            {
                gNotifyChars[0]->setValue((uint8_t *)(s + offset), chunkLen);
                gNotifyChars[0]->notify();
                anySent = true;
            }
        }

        offset += chunkLen;
        delay(25);
    }

    // Luôn gửi newline delimiter ở cuối để Flutter buffer split chính xác
    delay(10);
    for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
    {
        if (gPhones[i].state >= BLE_CONNECTED && gNotifyChars[0])
        {
            gNotifyChars[0]->setValue((uint8_t *)"\n", 1);
            gNotifyChars[0]->notify();
        }
    }

    gBleWarnedSendText = false; // Reset warning khi gửi thành công
    return anySent;
}

// =========================
// HEARTBEAT
// =========================

void ble_manager_send_heartbeat()
{
    if (!gHeartbeatNotifyChar)
        return;

    bool anyConnected = false;
    for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
    {
        if (gPhones[i].state >= BLE_CONNECTED)
        {
            anyConnected = true;
            break;
        }
    }
    if (!anyConnected)
        return;

    gHeartbeatNotifyChar->setValue((uint8_t *)"PING", 4);
    gHeartbeatNotifyChar->notify();
}

void ble_manager_heartbeat_loop()
{
    uint32_t now = millis();

    // Gửi heartbeat định kỳ
    if (now - gLastHeartbeatSendMs >= BLE_HEARTBEAT_INTERVAL_MS)
    {
        gLastHeartbeatSendMs = now;
        ble_manager_send_heartbeat();
    }

    // Kiểm tra timeout
    for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
    {
        if (gPhones[i].state >= BLE_CONNECTED)
        {
            uint32_t elapsed = now - gPhones[i].lastHeartbeatMs;
            if (elapsed > BLE_HEARTBEAT_TIMEOUT_MS)
            {
                // Chỉ log một lần, tránh spam serial
                if (!gPhones[i].heartbeatTimeoutLogged)
                {
                    Serial.printf("[BLE][TIMEOUT][Phone%d] Heartbeat timeout %lu ms\n",
                                  i, (unsigned long)elapsed);
                    gPhones[i].heartbeatTimeoutLogged = true;
                }
                gPhones[i].state = BLE_CONNECTED; // vẫn connected nhưng không khỏe
            }
        }
    }

    // Tự động restart advertising nếu không có phone nào kết nối
    if (!ble_manager_is_any_connected() &&
        (now - gLastAdvRestartMs > BLE_RECONNECT_DELAY_MS))
    {
        gLastAdvRestartMs = now;
        if (!NimBLEDevice::getAdvertising()->isAdvertising())
        {
            NimBLEDevice::startAdvertising();
            Serial.println("[BLE][ADV] Tu dong phat lai tin hieu");
        }
    }
}

// =========================
// TRẠNG THÁI KẾT NỐI
// =========================

bool ble_manager_is_any_connected()
{
    for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
    {
        if (gPhones[i].state >= BLE_CONNECTED)
            return true;
    }
    return false;
}

bool ble_manager_is_primary_connected()
{
    for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
    {
        if (gPhones[i].isPrimary && gPhones[i].state >= BLE_CONNECTED)
            return true;
    }
    return false;
}

int ble_manager_connected_count()
{
    int count = 0;
    for (int i = 0; i < BLE_MAX_CONNECTIONS; i++)
    {
        if (gPhones[i].state >= BLE_CONNECTED)
            count++;
    }
    return count;
}

const BlePhoneInfo *ble_manager_get_phone_info(int index)
{
    if (index < 0 || index >= BLE_MAX_CONNECTIONS)
        return nullptr;
    return &gPhones[index];
}

BleConnectionStats ble_manager_get_stats()
{
    return gStats;
}

// =========================
// GETTERS TRẠNG THÁI (API cũ)
// =========================

bool ble_is_stream_on() { return gBleStreamOn; }

bool ble_take_ack()
{
    bool r = gBleAck;
    gBleAck = false;
    return r;
}

bool ble_take_sos()
{
    bool r = gBleSos;
    gBleSos = false;
    return r;
}

bool ble_take_test_impact()
{
    bool r = gBleTestImpact;
    gBleTestImpact = false;
    return r;
}
