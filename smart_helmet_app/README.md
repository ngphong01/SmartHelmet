# 🪖 SmartHelmet - Flutter App

Ứng dụng Flutter điều khiển **Mũ Bảo Hiểm Thông Minh** qua Bluetooth LE (Nordic UART Service).

## 🚀 Cài đặt & Chạy

### Yêu cầu

- [Flutter SDK](https://flutter.dev/docs/get-started/install) >= 3.2.0
- Android Studio hoặc Xcode
- Điện thoại Android/iOS hoặc Emulator

### Cài đặt

```bash
cd smart_helmet_app
flutter pub get
```

### Chạy

```bash
# Android
flutter run

# iOS (chỉ trên macOS)
flutter run -d ios

# Build APK
flutter build apk --release
```

## 📁 Cấu trúc Project

```
lib/
├── main.dart                    # Entry point + MaterialApp
├── models/
│   └── telemetry_data.dart      # Model cho dữ liệu JSON từ mũ
├── services/
│   └── ble_service.dart         # Bluetooth LE (Nordic UART)
├── screens/
│   ├── home_screen.dart         # Màn hình chính (Map + Stats + Điều khiển)
│   └── impact_alert_screen.dart # Màn hình cảnh báo va chạm (fullscreen)
└── widgets/
    ├── connection_status.dart   # Badge trạng thái kết nối
    ├── gps_map.dart             # Bản đồ OpenStreetMap
    ├── stats_grid.dart          # Lưới thống kê (G, AI%, Sats, Speed)
    └── control_buttons.dart     # Nút TÔI ỔN & SOS
```

## 🔗 Giao thức BLE

| Service     | UUID                                   |
| ----------- | -------------------------------------- |
| Nordic UART | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` |
| TX (Notify) | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |
| RX (Write)  | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` |

## 🎮 Lệnh điều khiển

| Lệnh    | Mô tả                  |
| ------- | ---------------------- |
| `START` | Bắt đầu stream dữ liệu |
| `STOP`  | Dừng stream            |
| `ACK`   | Xác nhận an toàn       |
| `SOS`   | Gửi tín hiệu cứu hộ    |

## 📦 Dependencies

- `flutter_blue_plus` - Bluetooth LE
- `flutter_map` + `latlong2` - Bản đồ OpenStreetMap (miễn phí)
- `provider` - State management
- `geolocator` - GPS thiết bị
