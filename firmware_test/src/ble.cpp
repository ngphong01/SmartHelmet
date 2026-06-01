#include <NimBLEDevice.h>
#include "ble.h"

static const char *UART_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
static const char *UART_CHAR_RX_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
static const char *UART_CHAR_TX_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

static NimBLECharacteristic *pNotifyChar = nullptr;

// trạng thái điều khiển
static bool gBleStreamOn = false;
static volatile bool gBleAck = false;
static volatile bool gBleSos = false;
static volatile bool gBleTestImpact = false;

class UartRxCallback : public NimBLECharacteristicCallbacks
{
  void onWrite(NimBLECharacteristic *c) override
  {
    std::string v = c->getValue();
    Serial.print("[BLE][NHAN] Lenh tu app: ");
    Serial.println(v.c_str());

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
      Serial.println("[BLE][OK] App da xac nhan nguoi dung an toan");
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
  }
};

class ServerCallbacks : public NimBLEServerCallbacks
{
  void onConnect(NimBLEServer *s, ble_gap_conn_desc *desc) override
  {
    Serial.println("[BLE][OK] Dien thoai da ket noi");
  }
  void onDisconnect(NimBLEServer *s) override
  {
    Serial.println("[BLE][INFO] Dien thoai ngat ket noi, phat lai SmartHelmet");
    NimBLEDevice::startAdvertising();
  }
};

void ble_init()
{
  NimBLEDevice::init("SmartHelmet");
  NimBLEDevice::setMTU(185); // cho phép packet to hơn

  NimBLEServer *server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService *svc = server->createService(UART_SERVICE_UUID);

  pNotifyChar = svc->createCharacteristic(
      UART_CHAR_TX_UUID,
      NIMBLE_PROPERTY::NOTIFY);

  NimBLECharacteristic *pRx = svc->createCharacteristic(
      UART_CHAR_RX_UUID,
      NIMBLE_PROPERTY::WRITE);
  pRx->setCallbacks(new UartRxCallback());

  svc->start();

  NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(svc->getUUID());
  adv->setScanResponse(true);
  adv->start();

  Serial.println("[OK][BLE] Dang phat tin hieu ten SmartHelmet");
}

void ble_send_bytes(const uint8_t *data, size_t len)
{
  if (!pNotifyChar)
    return;
  pNotifyChar->setValue(data, len);
  pNotifyChar->notify();
}

void ble_send_text(const char *s)
{
  if (!pNotifyChar)
    return;
  size_t len = strlen(s);
  if (len == 0)
    return;

  // MTU=185 → payload tối đa 182 byte (185 - 3 byte ATT header)
  // Dùng 180 byte để an toàn, chừa 2 byte dư
  const size_t CHUNK = 180;

  size_t offset = 0;
  while (offset < len)
  {
    size_t chunkLen = (len - offset > CHUNK) ? CHUNK : (len - offset);

    // Gộp \n vào chunk CUỐI CÙNG để tiết kiệm 1 notify
    if (offset + chunkLen >= len && chunkLen < CHUNK)
    {
      // Chunk cuối còn đủ chỗ để nhét \n
      uint8_t buf[CHUNK + 1];
      memcpy(buf, s + offset, chunkLen);
      buf[chunkLen] = '\n';
      pNotifyChar->setValue(buf, chunkLen + 1);
    }
    else
    {
      pNotifyChar->setValue((uint8_t *)(s + offset), chunkLen);
    }

    pNotifyChar->notify();
    offset += chunkLen;

    // Delay 25ms giữa các chunk để BLE stack kịp gửi
    // Tránh notify() ghi đè buffer nội bộ khi stack còn bận
    delay(25);
  }

  // Nếu chunk cuối đã đầy 180 byte (không nhét được \n) → gửi \n riêng
  if (len > 0)
  {
    size_t lastChunkLen = len % CHUNK;
    if (lastChunkLen == 0)
      lastChunkLen = CHUNK; // trường hợp len chia hết cho 180

    // \n đã được gộp vào chunk cuối nếu lastChunkLen < CHUNK
    // Chỉ cần gửi \n riêng nếu chunk cuối đầy 180 byte
    if (lastChunkLen == CHUNK)
    {
      delay(10);
      pNotifyChar->setValue((uint8_t *)"\n", 1);
      pNotifyChar->notify();
    }
  }

  Serial.printf("[BLE][TX] Da gui %u bytes JSON (%d chunk)\n", (unsigned)len, (int)((len + CHUNK - 1) / CHUNK));
}

// ======= getters trạng thái =======

bool ble_is_stream_on()
{
  return gBleStreamOn;
}

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
