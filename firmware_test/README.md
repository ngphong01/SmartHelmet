# 🪖 SmartHelmet — Mũ Bảo Hiểm Thông Minh

Hệ thống mũ bảo hiểm tích hợp AI phát hiện va chạm & ngã xe, tự động gọi cứu hộ qua Flutter app.

## 🎯 Mục đích

Phát hiện tai nạn giao thông theo thời gian thực và tự động gửi cảnh báo khẩn cấp đến:
- **Telegram** — tin nhắn tức thời qua WiFi
- **Flutter App** — gọi điện + voice TTS qua BLE
- **BLE Mesh** — broadcast cho các mũ lân cận

## 🧠 Cách hoạt động

```
┌─────────────────────────────────────────────────────────┐
│                    ESP32 (Mũ bảo hiểm)                   │
│                                                         │
│  MPU6500 IMU ──→ 1000Hz sampling ──→ FFT + AI Model     │
│       ↓                                                 │
│  Phát hiện:  Va chạm (p>0.85 + peak>2g)                 │
│              Ngã xe  (tilt>55° + gyro>120°/s)            │
│       ↓                                                 │
│  GPS NEO-6M + Phone GPS (BLE) ──→ GPS Selector          │
│       ↓                                                 │
│  Cảnh báo:  Telegram (WiFi) + BLE notify + BLE Mesh     │
└─────────────────────────────────────────────────────────┘
                           ↓ BLE
┌─────────────────────────────────────────────────────────┐
│                   Flutter App (Điện thoại)                │
│                                                         │
│  Nhận impact_alert qua BLE ──→ FallAlertScreen           │
│       ↓                                                 │
│  Đếm ngược 30s ──→ Gọi người thân 1                     │
│       ↓                                                 │
│  Gọi người thân 2 ──→ 🔊 Voice TTS (đọc to qua loa)     │
└─────────────────────────────────────────────────────────┘
```

## 📁 Cấu trúc dự án

```
firmware_test/
├── platformio.ini          # PlatformIO config (ESP32)
├── src/                    # Firmware ESP32
│   ├── main.cpp            # Main loop + detection logic
│   ├── imu.cpp/h           # MPU6500 driver
│   ├── gps.cpp/h           # NEO-6M NMEA parser
│   ├── gps_selector.cpp/h  # GPS source selection (NEO-6M vs Phone)
│   ├── gps_cache.cpp/h     # GPS RTC memory cache
│   ├── fall_detector.cpp/h # Tilt + gyro fall detection
│   ├── ml_model.cpp/h      # Logistic Regression AI model
│   ├── fft_features.cpp/h  # FFT feature extraction
│   ├── ble_manager.cpp/h   # BLE dual-phone connection
│   ├── ble_mesh.cpp/h      # BLE Mesh impact broadcast
│   ├── ble_emergency_beacon.cpp/h # SOS beacon (no pairing)
│   ├── wifi_manager.cpp/h  # Multi-SSID WiFi
│   ├── telegram.cpp/h      # Telegram bot alerts
│   ├── impact_buffer.cpp/h # Impact event buffer + retry
│   ├── ride_state.cpp/h    # State machine (IDLE/RIDING/IMPACT/FALLEN/SOS)
│   ├── train_on_device.cpp/h # On-device ML training
│   ├── training_data.cpp/h # Preloaded training data
│   ├── data_recorder.cpp/h # Circular buffer recorder
│   ├── config.h            # Pin definitions + constants
│   └── ...
├── flutter_app/            # Flutter mobile app
│   └── lib/
│       ├── main.dart       # App entry + ConnectScreen + Dashboard
│       ├── screens/
│       │   └── fall_alert_screen.dart  # Emergency alert UI
│       └── services/
│           ├── ble_service.dart        # BLE connection + parsing
│           ├── emergency_service.dart  # Phone call + SMS
│           ├── voice_service.dart      # TTS voice alert
│           └── beacon_scanner.dart     # BLE emergency beacon scanner
├── include/
│   └── secrets.h           # WiFi + Telegram credentials (gitignored)
├── tools/
│   ├── evaluate_model.py   # Model evaluation script
│   └── generate_alarm.py   # Alarm sound generator
└── docs/
    └── ml_evaluation/      # ML model evaluation data
```

## 🔧 Phần cứng

| Module | Model | Kết nối |
|--------|-------|---------|
| MCU | ESP32 Dev Module | — |
| IMU | MPU6500 | I2C (SDA=21, SCL=22) |
| GPS | GY-NEO6MV2 | UART2 (RX=16, TX=17) |
| Buzzer | Active buzzer | GPIO |

## 🚀 Cài đặt & Build

### Firmware (ESP32)

```bash
# Cài PlatformIO
pip install platformio

# Build
cd firmware_test
pio run

# Upload
pio run --target upload

# Monitor
pio device monitor
```

### Flutter App

```bash
cd firmware_test/flutter_app
flutter pub get
flutter run
```

## ⚙️ Cấu hình

### Ngưỡng phát hiện (config.h + fall_detector.h)

| Tham số | Mặc định | Mô tả |
|---------|----------|-------|
| `IMPACT_THRESH` | 0.85 | Ngưỡng xác suất AI |
| `PEAK_G_MIN` | 2.0g | Gia tốc tối thiểu |
| `BRUTE_FORCE_G_MIN` | 5.0g | Bypass AI |
| `FALL_TILT_THRESHOLD_DEG` | 55° | Góc nghiêng ngã |
| `FALL_GYRO_THRESHOLD_DPS` | 120°/s | Vận tốc góc ngã |
| `IMPACT_DEBOUNCE_MS` | 5000 | Debounce va chạm |

### WiFi & Telegram (include/secrets.h)

```cpp
#define WIFI_SSID "your_wifi"
#define WIFI_PASS "your_password"
#define TELEGRAM_BOT_TOKEN "your_bot_token"
#define TELEGRAM_CHAT_ID "your_chat_id"
#define EMERGENCY_PHONE "phone_number"
```

## 🔒 Bảo mật

⚠️ **Cảnh báo:** `include/secrets.h` chứa credentials nhạy cảm. **KHÔNG** commit file này. Đã được thêm vào `.gitignore`. Dùng `include/secrets.h.example` làm mẫu.

## 📊 Hiệu năng

- Sample rate: **1000 Hz** (IMU)
- Inference: **500ms/cửa sổ** (FFT 512 điểm, overlap 50%)
- RAM: ~102KB / 320KB (31%)
- Flash: ~1.5MB / 2MB (80%)
- BLE: 2 phones simultaneous, MTU 185, heartbeat 5s

## 🧪 Test

Đập nhẹ vào mũ để test:
1. ESP32 phát hiện va chạm/ngã → gửi Telegram + BLE
2. Flutter app hiện màn hình đếm ngược 30s
3. Hết 30s → tự động gọi điện + voice TTS
4. Bấm "TÔI ỔN" để hủy

## 📝 License

MIT
