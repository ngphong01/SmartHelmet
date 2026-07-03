# 🪖 SmartHelmet

<div align="center">

**Mũ bảo hiểm thông minh tích hợp AI — phát hiện va chạm & ngã xe, tự động gọi cứu hộ**

[![PlatformIO](https://img.shields.io/badge/PlatformIO-ESP32-orange?logo=platformio)](https://platformio.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Active-brightgreen)]()

</div>

---

## 📌 Overview

**SmartHelmet** là hệ thống mũ bảo hiểm nhúng tích hợp AI chạy trên **ESP32**, có khả năng phát hiện tai nạn giao thông theo thời gian thực và tự động gửi cảnh báo khẩn cấp đến người thân qua nhiều kênh liên lạc.

```
┌─────────────────────────────────────────────────────────┐
│                    ESP32 (Firmware)                      │
│                                                         │
│  MPU6500 IMU ──→ 1000Hz sampling ──→ FFT + AI Model     │
│                                                         │
│  Detect:  Impact  (p > 0.85  &&  peak > 2g)             │
│           Fall    (tilt > 55°  &&  gyro > 120°/s)       │
│                                                         │
│  GPS NEO-6M  ──┐                                        │
│  Phone GPS ────┴──→ GPS Selector ──→ Best Source        │
│                                                         │
│  Alert:   Telegram (WiFi)                               │
│           BLE Notify ──→ Flutter App                    │
│           BLE Mesh  ──→ Nearby Helmets                  │
└─────────────────────────────────────────────────────────┘
                        │ BLE
                        ▼
┌─────────────────────────────────────────────────────────┐
│                  Flutter App (Mobile)                    │
│                                                         │
│  impact_alert ──→ FallAlertScreen ──→ Countdown 30s     │
│                                                         │
│  → Call Contact #1 → Call Contact #2                   │
│  → 🔊 TTS Voice Alert (Speaker)                         │
└─────────────────────────────────────────────────────────┘
```

---

## ✨ Features

- 🧠 **AI Impact Detection** — Logistic Regression + FFT 512-point, inference 500ms/window
- 🏍️ **Fall Detection** — Tilt angle + gyroscope fusion algorithm
- 📡 **Multi-channel Alert** — Telegram Bot, BLE notify, BLE Mesh broadcast
- 📱 **Flutter App** — Auto phone call + Text-to-Speech voice alert
- 🛰️ **GPS Selector** — Tự động chọn NEO-6M hoặc Phone GPS (nguồn tốt hơn)
- 🔦 **BLE Emergency Beacon** — SOS broadcast không cần ghép đôi
- 💾 **Impact Buffer** — NVS persistence + retry khi mất kết nối
- 🔄 **State Machine** — `IDLE → RIDING → IMPACT → FALLEN → SOS`

---

## 📁 Project Structure

```
SmartHelmet/
├── firmware_test/
│   ├── platformio.ini              # PlatformIO build config
│   ├── include/
│   │   ├── config.h                # Pin definitions & thresholds
│   │   └── secrets.h.example       # Credentials template (gitignored)
│   └── src/
│       ├── main.cpp                # Entry point & main loop
│       │
│       ├── imu.cpp / imu.h                     # MPU6500 I2C driver
│       ├── gps.cpp / gps.h                     # NEO-6M NMEA parser
│       ├── gps_selector.cpp / gps_selector.h   # GPS source selector
│       ├── gps_cache.cpp / gps_cache.h         # GPS RTC memory cache
│       │
│       ├── fall_detector.cpp / fall_detector.h # Tilt + gyro fall detection
│       ├── ml_model.cpp / ml_model.h           # Logistic Regression model
│       ├── fft_features.cpp / fft_features.h   # FFT feature extraction
│       ├── train_on_device.cpp                 # On-device ML training
│       ├── training_data.cpp                   # Preloaded training dataset
│       │
│       ├── ble_manager.cpp / ble_manager.h         # BLE dual-phone connection
│       ├── ble_mesh.cpp / ble_mesh.h               # BLE Mesh broadcast
│       ├── ble_emergency_beacon.cpp                # SOS beacon (no pairing)
│       │
│       ├── wifi_manager.cpp / wifi_manager.h   # Multi-SSID WiFi manager
│       ├── telegram.cpp / telegram.h           # Telegram Bot alerts
│       ├── impact_buffer.cpp / impact_buffer.h # Event buffer & retry
│       ├── ride_state.cpp / ride_state.h       # Ride state machine
│       └── data_recorder.cpp / data_recorder.h # Circular buffer recorder
│
├── flutter_app/
│   └── lib/
│       ├── main.dart                           # App entry, ConnectScreen
│       ├── screens/
│       │   └── fall_alert_screen.dart          # Emergency countdown UI
│       └── services/
│           ├── ble_service.dart                # BLE connection & parsing
│           ├── emergency_service.dart          # Phone call & SMS
│           ├── voice_service.dart              # TTS voice alert
│           └── beacon_scanner.dart             # BLE beacon scanner
│
├── tools/
│   ├── evaluate_model.py           # Model accuracy evaluation
│   └── generate_alarm.py           # Alarm audio generator
│
└── docs/
    └── ml_evaluation/              # ML model evaluation reports
```

---

## 🔧 Hardware

| Component | Model | Interface |
|-----------|-------|-----------|
| MCU | ESP32 Dev Module | — |
| IMU | MPU6500 | I2C — SDA `GPIO21`, SCL `GPIO22` |
| GPS | GY-NEO6MV2 | UART2 — RX `GPIO16`, TX `GPIO17` |
| Buzzer | Active Buzzer | GPIO |

---

## ⚙️ Configuration

### Detection Thresholds — `config.h` / `fall_detector.h`

| Parameter | Default | Description |
|-----------|---------|-------------|
| `IMPACT_THRESH` | `0.85` | AI probability threshold |
| `PEAK_G_MIN` | `2.0g` | Minimum impact acceleration |
| `BRUTE_FORCE_G_MIN` | `5.0g` | Bypass AI threshold |
| `FALL_TILT_THRESHOLD_DEG` | `55°` | Tilt angle for fall detection |
| `FALL_GYRO_THRESHOLD_DPS` | `120°/s` | Angular velocity for fall |
| `IMPACT_DEBOUNCE_MS` | `5000ms` | Impact debounce window |

### Credentials — `include/secrets.h`

> ⚠️ File này đã được thêm vào `.gitignore`. Dùng `secrets.h.example` làm template.

```cpp
#define WIFI_SSID            "your_wifi_ssid"
#define WIFI_PASS            "your_wifi_password"
#define TELEGRAM_BOT_TOKEN   "your_bot_token"
#define TELEGRAM_CHAT_ID     "your_chat_id"
#define EMERGENCY_PHONE      "0909xxxxxx"
```

---

## 🚀 Getting Started

### Prerequisites

- [PlatformIO](https://platformio.org/install) CLI hoặc VS Code Extension
- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.0
- ESP32 Dev Module + các module phần cứng bên trên

### 1. Clone

```bash
git clone https://github.com/your-username/SmartHelmet.git
cd SmartHelmet
```

### 2. Firmware

```bash
cd firmware_test

# Copy credentials template
cp include/secrets.h.example include/secrets.h
# Điền thông tin WiFi & Telegram vào secrets.h

# Build
pio run

# Flash
pio run --target upload

# Serial monitor
pio device monitor --baud 115200
```

### 3. Flutter App

```bash
cd firmware_test/flutter_app

flutter pub get
flutter run
```

---

## 📊 Performance

| Metric | Value |
|--------|-------|
| IMU Sample Rate | 1000 Hz |
| AI Inference Window | 500ms (FFT 512-point, 50% overlap) |
| RAM Usage | ~102 KB / 320 KB (31%) |
| Flash Usage | ~1.5 MB / 2 MB (75%) |
| BLE Connections | 2 phones simultaneous |
| BLE MTU | 185 bytes |
| BLE Heartbeat | 5s interval |

---

## 🧪 Quick Test

```
1. Đập nhẹ vào mũ hoặc nghiêng > 55°
2. ESP32 → phát hiện → gửi Telegram + BLE notify
3. Flutter App → hiển thị FallAlertScreen → đếm ngược 30s
4. Hết 30s → tự động gọi Contact #1 → Contact #2 → TTS voice
5. Nhấn "TÔI ỔN" để hủy cảnh báo
```

---

## 🗺️ Roadmap

### ✅ Completed

- [x] AI impact detection — Logistic Regression + FFT
- [x] Fall detection — tilt + gyro fusion
- [x] GPS Selector — NEO-6M vs Phone GPS auto-switching
- [x] BLE dual-phone connection + heartbeat
- [x] Telegram alert over WiFi
- [x] BLE Mesh broadcast to nearby helmets
- [x] BLE Emergency Beacon (no pairing required)
- [x] Flutter app — auto call + TTS voice alert
- [x] Impact buffer + NVS retry persistence

### 🚧 In Progress

- [ ] Vietnamese TTS engine — fallback support
- [ ] Flutter background service — receive alerts when app is killed
- [ ] SIM800L SMS — direct SMS from ESP32 without WiFi
- [ ] OTA firmware update — remote update over WiFi / BLE

### 📋 Planned

- [ ] Multi-helmet mesh relay network
- [ ] Cloud dashboard — realtime GPS tracking & status
- [ ] AI model fine-tuning with real-world data
- [ ] Li-Po battery + USB-C charging circuit
- [ ] IP65 waterproof enclosure design
- [ ] Helmet-removed detection alert
- [ ] PPG heart rate sensor integration
- [ ] Auto-call 115 (emergency services)
- [ ] BLE indoor positioning (GPS-denied environments)
- [ ] Cloud sync for training data improvement

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.

---

<div align="center">

Made with ❤️ by **Đào Văn Phong**

*ESP32 · Flutter · BLE · AI · GPS*

</div>
