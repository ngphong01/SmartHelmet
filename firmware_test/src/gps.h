#pragma once
#include <Arduino.h>

struct GpsFix {
  bool valid = false;
  double lat = 0.0;
  double lon = 0.0;
  float speedKmh = 0.0f;
  uint8_t satellites = 0;
  float hdop = 0.0f;
  uint8_t hour = 0;
  uint8_t minute = 0;
  uint8_t second = 0;
  uint8_t day = 0;
  uint8_t month = 0;
  uint16_t year = 0;
  uint32_t lastUpdateMs = 0;
};

void gps_init();
void gps_poll();
bool gps_get_fix(GpsFix& out);
