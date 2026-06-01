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
  // Thêm \n để Flutter parser nhận biết kết thúc dòng JSON
  char buf[len + 2];
  memcpy(buf, s, len);
  buf[len] = '\n';
  buf[len + 1] = '\0';
  pNotifyChar->setValue((uint8_t *)buf, len + 1);
  pNotifyChar->notify();
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
