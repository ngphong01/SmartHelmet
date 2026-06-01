#include "gps.h"
#include "config.h"

static HardwareSerial GPSSerial(2);
static GpsFix gFix;
static char lineBuf[160];
static size_t lineLen = 0;

static bool isHex(char c)
{
  return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f');
}

static uint8_t hexValue(char c)
{
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'A' && c <= 'F')
    return 10 + (c - 'A');
  if (c >= 'a' && c <= 'f')
    return 10 + (c - 'a');
  return 0;
}

static bool verifyChecksum(const char *s)
{
  if (!s || s[0] != '$')
    return false;
  const char *star = strchr(s, '*');
  if (!star || !isHex(star[1]) || !isHex(star[2]))
    return false;

  uint8_t cs = 0;
  for (const char *p = s + 1; p < star; ++p)
    cs ^= (uint8_t)*p;
  uint8_t expected = (hexValue(star[1]) << 4) | hexValue(star[2]);
  return cs == expected;
}

static bool parseTimeField(const char *s, uint8_t &hh, uint8_t &mm, uint8_t &ss)
{
  if (!s || strlen(s) < 6)
    return false;
  hh = (uint8_t)((s[0] - '0') * 10 + (s[1] - '0'));
  mm = (uint8_t)((s[2] - '0') * 10 + (s[3] - '0'));
  ss = (uint8_t)((s[4] - '0') * 10 + (s[5] - '0'));
  return true;
}

static bool parseDateField(const char *s, uint8_t &dd, uint8_t &mo, uint16_t &yy)
{
  if (!s || strlen(s) < 6)
    return false;
  dd = (uint8_t)((s[0] - '0') * 10 + (s[1] - '0'));
  mo = (uint8_t)((s[2] - '0') * 10 + (s[3] - '0'));
  yy = 2000 + (uint16_t)((s[4] - '0') * 10 + (s[5] - '0'));
  return true;
}

static double parseLatLon(const char *value, const char hemi)
{
  if (!value || !*value)
    return 0.0;
  double raw = atof(value);
  int deg = (int)(raw / 100.0);
  double min = raw - (deg * 100.0);
  double dec = deg + (min / 60.0);
  if (hemi == 'S' || hemi == 'W')
    dec = -dec;
  return dec;
}

static int splitFields(char *s, char *fields[], int maxFields)
{
  int count = 0;
  char *p = s;
  fields[count++] = p;
  while (*p && count < maxFields)
  {
    if (*p == ',')
    {
      *p = '\0';
      fields[count++] = p + 1;
    }
    ++p;
  }
  return count;
}

static void parseRmc(char *fields[], int n)
{
  if (n < 12)
    return;
  if (!fields[2] || fields[2][0] != 'A')
    return;

  gFix.lat = parseLatLon(fields[3], fields[4] ? fields[4][0] : 'N');
  gFix.lon = parseLatLon(fields[5], fields[6] ? fields[6][0] : 'E');
  gFix.speedKmh = fields[7] && *fields[7] ? atof(fields[7]) * 1.852f : 0.0f;

  uint8_t hh = 0, mm = 0, ss = 0;
  uint8_t dd = 0, mo = 0;
  uint16_t yy = 0;
  if (parseTimeField(fields[1], hh, mm, ss))
  {
    gFix.hour = hh;
    gFix.minute = mm;
    gFix.second = ss;
  }
  if (parseDateField(fields[9], dd, mo, yy))
  {
    gFix.day = dd;
    gFix.month = mo;
    gFix.year = yy;
  }

  gFix.valid = true;
  gFix.lastUpdateMs = millis();
}

static void parseGga(char *fields[], int n)
{
  if (n < 15)
    return;
  int fixQuality = fields[6] && *fields[6] ? atoi(fields[6]) : 0;
  if (fixQuality <= 0)
    return;

  gFix.lat = parseLatLon(fields[2], fields[3] ? fields[3][0] : 'N');
  gFix.lon = parseLatLon(fields[4], fields[5] ? fields[5][0] : 'E');
  gFix.satellites = fields[7] && *fields[7] ? (uint8_t)atoi(fields[7]) : 0;
  gFix.hdop = fields[8] && *fields[8] ? atof(fields[8]) : 0.0f;
  gFix.valid = true;
  gFix.lastUpdateMs = millis();
}

static void processLine(char *line)
{
  if (!line || line[0] != '$')
    return;
  if (!verifyChecksum(line))
    return;

  char *star = strchr(line, '*');
  if (star)
    *star = '\0';

  char *fields[20] = {0};
  int n = splitFields(line + 1, fields, 20);
  if (n <= 0)
    return;

  const char *type = fields[0];
  if (!type)
    return;

  if (strcmp(type, "GPRMC") == 0 || strcmp(type, "GNRMC") == 0)
  {
    parseRmc(fields, n);
  }
  else if (strcmp(type, "GPGGA") == 0 || strcmp(type, "GNGGA") == 0)
  {
    parseGga(fields, n);
  }
}

void gps_init()
{
  GPSSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  lineLen = 0;
  gFix = GpsFix{};
  Serial.println("[GPS] Khoi tao Serial2 (RX=16, TX=17, Baud=9600)");
  Serial.println("[GPS] Neu khong thay NMEA sau 10s: kiem tra day TX/RX hoac baud rate");
}

void gps_poll()
{
  while (GPSSerial.available())
  {
    char c = (char)GPSSerial.read();
    if (c == '\r')
      continue;
    if (c == '\n')
    {
      lineBuf[lineLen] = '\0';
      if (lineLen > 0)
      {
        // Debug: in raw NMEA ra Serial
        Serial.println(lineBuf);
        processLine(lineBuf);
      }
      lineLen = 0;
      continue;
    }

    if (lineLen < sizeof(lineBuf) - 1)
    {
      lineBuf[lineLen++] = c;
    }
    else
    {
      lineLen = 0;
    }
  }
}

bool gps_get_fix(GpsFix &out)
{
  out = gFix;
  return gFix.valid;
}
