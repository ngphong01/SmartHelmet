#include "ble.h"
#include "ble_manager.h"

// ============================================================
// WRAPPER - Goi xuong ble_manager de giu tuong thich API cu
// ============================================================
// Cac ham ble_is_stream_on, ble_take_ack, ble_take_sos,
// ble_take_test_impact duoc dinh nghia TRUC TIEP trong
// ble_manager.cpp (khong can wrapper).

void ble_init()
{
  ble_manager_init();
}

void ble_send_bytes(const uint8_t *data, size_t len)
{
  ble_manager_send_bytes(data, len);
}

void ble_send_text(const char *s)
{
  ble_manager_send_text(s);
}

bool ble_is_connected()
{
  return ble_manager_is_any_connected();
}

int ble_connection_count()
{
  return ble_manager_connected_count();
}
