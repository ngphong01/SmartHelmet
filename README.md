# 🪖 Hệ Thống Mũ Bảo Hiểm Thông Minh Ứng Dụng IoT & Machine Learning

## 📖 Giới thiệu

Dự án **Hệ thống Mũ Bảo Hiểm Thông Minh** được xây dựng nhằm nâng cao an toàn cho người tham gia giao thông, đặc biệt là người đi xe máy - đối tượng chiếm tỷ lệ cao nhất trong các vụ tai nạn giao thông tại Việt Nam.

Hệ thống sử dụng **ESP32** làm trung tâm xử lý, tích hợp:

- **Cảm biến gia tốc MPU6050** thu thập dữ liệu chuyển động 1000 mẫu/giây
- **GPS NEO-6M** định vị tọa độ thời gian thực
- **Bluetooth BLE** kết nối không dây với smartphone
- **WiFi + Telegram Bot** gửi cảnh báo khẩn cấp đến người thân

Khi phát hiện **va chạm giao thông**, hệ thống sẽ:

1. 🚨 Hiển thị màn hình cảnh báo trên App Flutter (rung, đếm ngược)
2. 📍 Gửi tọa độ GPS, tốc độ, xác suất va chạm qua BLE
3. 📞 Tự động gọi điện khẩn cấp sau 15 giây nếu nạn nhân bất tỉnh
4. 🆘 Tự động gửi SOS sau 30 giây
5. ✈️ Gửi cảnh báo qua Telegram Bot kèm vị trí Google Maps
6. ✅ Cho phép người đội bấm "TÔI ỔN" để hủy nếu không sao

---

## 🎯 Mục tiêu dự án

| STT | Mục tiêu                                                          | Trạng thái    |
| --- | ----------------------------------------------------------------- | ------------- |
| 1   | Phát hiện va chạm giao thông theo thời gian thực bằng IMU + AI    | ✅ Hoàn thành |
| 2   | Định vị GPS và gửi tọa độ tai nạn                                 | ✅ Hoàn thành |
| 3   | Phân biệt impact / non-impact bằng Logistic Regression trên ESP32 | ✅ Hoàn thành |
| 4   | Kết nối BLE với ứng dụng di động Flutter                          | ✅ Hoàn thành |
| 5   | Cảnh báo khẩn cấp qua Telegram + gọi điện tự động                 | ✅ Hoàn thành |
| 6   | Huấn luyện mô hình ML offline từ dữ liệu thực tế                  | ✅ Hoàn thành |
| 7   | Backend lưu trữ và quản lý dữ liệu                                | ✅ Hoàn thành |
| 8   | Mô phỏng và đánh giá hệ thống                                     | ✅ Hoàn thành |

---

## 🧠 Kiến trúc tổng thể hệ thống

```mermaid
graph TD
    subgraph "Phần cứng - Mũ bảo hiểm"
        MPU["MPU6050\nGia tốc 3 trục"] -->|I2C| ESP["ESP32\nXử lý trung tâm"]
        GPS["GPS NEO-6M\nĐịnh vị"] -->|UART| ESP
    end

    subgraph "Xử lý trên ESP32"
        ESP -->|1000 Hz| FFT["FFT 512 điểm\n5 dải tần"]
        FFT -->|8 features| LR["Logistic Regression\nOn-device Training"]
        LR -->|p(impact)| DECISION{"Phát hiện\nva chạm?"}
    end

    subgraph "Cảnh báo"
        DECISION -->|BLE| APP["Flutter App\nHiển thị GPS + Alert"]
        DECISION -->|WiFi| TG["Telegram Bot\nGửi vị trí + ảnh"]
        APP -->|Nút bấm| SOS["SOS / TÔI ỔN"]
    end

    subgraph "Lưu trữ"
        APP -->|HTTP| BE["Backend Node.js\nExpress + MongoDB"]
    end
```

### Cấu trúc thư mục

```
He-Thong-Mu-Bao-Hiem-Thong-Minh/
├── firmware_test/          # Firmware ESP32 (PlatformIO, C++)
│   ├── src/
│   │   ├── main.cpp            # Vòng lặp chính: sampling + detection
│   │   ├── imu.cpp/h           # Đọc MPU6050 qua I2C
│   │   ├── gps.cpp/h           # Parse NMEA GPS (GPRMC, GPGGA)
│   │   ├── ble.cpp/h           # Nordic UART BLE Service
│   │   ├── fft_features.cpp/h  # FFT 512 điểm, trích 5 dải tần
│   │   ├── ml_model.cpp/h      # Logistic Regression inference
│   │   ├── train_on_device.cpp/h  # Huấn luyện offline trên ESP32
│   │   ├── training_data.cpp/h # Dữ liệu huấn luyện có sẵn
│   │   ├── telegram.cpp/h      # WiFi + Telegram Bot API
│   │   ├── logger.cpp/h        # Stream IMU raw qua BLE
│   │   └── config.h            # Cấu hình pin, tham số
│   └── platformio.ini
│
├── smart_helmet_app/       # Ứng dụng di động Flutter
│   └── lib/
│       ├── main.dart               # Entry point + Provider
│       ├── services/ble_service.dart  # Kết nối BLE, buffer, parse JSON
│       ├── models/telemetry_data.dart # Model GPS, Impact
│       ├── screens/
│       │   ├── home_screen.dart        # Dashboard chính
│       │   └── impact_alert_screen.dart # Màn hình cảnh báo va chạm
│       └── widgets/
│           ├── gps_map.dart            # Bản đồ OpenStreetMap
│           ├── stats_grid.dart         # Grid cảm biến
│           ├── control_buttons.dart    # Nút TÔI ỔN, SOS, TEST
│           └── connection_status.dart  # Trạng thái kết nối
│
├── backend/                # Backend server (Node.js + Express + MongoDB)
├── data_logger/            # Công cụ thu thập & phân tích dữ liệu
│   ├── prep_and_train.py       # Tiền xử lý & huấn luyện ML
│   ├── analyze_fft.py          # Phân tích phổ FFT
│   ├── export_logit_to_c.py    # Xuất model sang C++ cho ESP32
│   └── *.csv                   # Dữ liệu thực nghiệm
│
└── simulator/              # Mô phỏng gửi telemetry lên backend
    └── simulator.js
```

---

## ⚙️ Phần cứng sử dụng

| Linh kiện                   | Vai trò                                       | Giao tiếp                       |
| --------------------------- | --------------------------------------------- | ------------------------------- |
| **ESP32 Dev Module**        | Vi điều khiển trung tâm                       | -                               |
| **MPU6050 (GY-521)**        | Cảm biến gia tốc 3 trục + con quay hồi chuyển | I2C (SDA=21, SCL=22)            |
| **GPS NEO-6M (GY-NEO6MV2)** | Định vị vệ tinh GPS                           | UART2 (RX=16, TX=17, Baud=9600) |
| **Smartphone Android**      | Hiển thị, cảnh báo, gọi điện                  | BLE 4.0+                        |

---

## 📊 Xử lý tín hiệu & Machine Learning

### 🔹 Quy trình xử lý

```
IMU 1000Hz → |a| = √(ax²+ay²+az²) → Buffer 512 mẫu (~512ms)
    → FFT 512 điểm → 5 dải tần năng lượng
    → [F0, F1, F2, F3, F4, ax, ay, az] = 8 features
    → Logistic Regression → p(impact) ∈ [0, 1]
    → p > threshold AND peak_g > PEAK_G_MIN → VA CHẠM!
```

### 🔹 5 dải tần FFT

| Band | Tần số (Hz) | Ý nghĩa vật lý                       |
| ---- | ----------- | ------------------------------------ |
| 0    | 0.5 – 4     | Chuyển động nền (rung xe, đường xóc) |
| 1    | 4 – 8       | Rung động mạnh (ổ gà, phanh gấp)     |
| 2    | 12 – 20     | Bắt đầu va chạm (biến dạng mũ)       |
| 3    | 20 – 40     | Va đập chính (truyền xung lực)       |
| 4    | 40 – 80     | Xung lực tần số cao (nứt vỡ)         |

### 🔹 Mô hình Logistic Regression

- **Input**: 8 features (5 FFT + 3 accel raw)
- **Output**: Xác suất va chạm `p ∈ [0, 1]`
- **Training**: Gradient Descent offline trên ESP32 với dữ liệu thực tế
- **Ngưỡng phát hiện**:
  - Chế độ thường: `p > 0.97` AND `peak_g > 2.8g`
  - Chế độ test: `p > 0.25` AND `peak_g > 0.8g`

### 🔹 Cơ chế chống nhiễu

- **Peak G filter**: Chỉ xét nếu gia tốc đỉnh vượt ngưỡng
- **Confirm windows**: Cần 1-2 cửa sổ liên tiếp xác nhận
- **Debounce**: 5 giây giữa các lần cảnh báo

---

## 📱 Ứng dụng di động (Flutter)

### Màn hình chính (Dashboard)

- 🗺️ **Bản đồ GPS** real-time với OpenStreetMap + marker vị trí
- 📊 **Grid cảm biến**: Đỉnh G, AI dự đoán, số vệ tinh, tốc độ
- 🎮 **Nút điều khiển**: TÔI ỔN, SOS, TEST VA CHẠM
- 📡 **Dữ liệu thô JSON** debug

### Màn hình cảnh báo va chạm

- 🚨 Animation rung đỏ + đếm ngược
- ✅ **TÔI ỔN**: Người đội xác nhận an toàn → gửi ACK
- 🆘 **SOS**: Gửi tín hiệu cấp cứu khẩn cấp
- 📞 **GỌI CỨU HỘ**: Gọi trực tiếp số điện thoại khẩn cấp
- ⏱ Tự động SOS sau 30 giây nếu không phản hồi
- ⏱ Tự động gọi điện sau 15 giây

### Giao thức BLE

- **Service**: Nordic UART (`6e400001-b5a3-f393-e0a9-e50e24dcca9e`)
- **TX (Notify)**: ESP32 → App, JSON 340-500 byte, chunk 180B + `\n`
- **RX (Write)**: App → ESP32, lệnh `START`/`STOP`/`ACK`/`SOS`/`TEST_IMPACT`
- **MTU**: Negotiate 512, fallback 185

---

## ✈️ Cảnh báo Telegram

Khi phát hiện va chạm, ESP32 gửi tin nhắn qua Telegram Bot:

```
🚨 CẢNH BÁO VA CHẠM!
👤 Mũ: H001
🕐 Thời gian: 2026-06-02 12:34:56
📍 Vị trí: 21.02845, 105.83591
🗺️ Google Maps: https://maps.google.com/?q=21.02845,105.83591
⚡ Đỉnh gia tốc: 2.35g
🧠 AI xác suất: 98.5%
🏍️ Tốc độ: 45.2 km/h
```

---

## 🌐 Backend (Node.js)

- **Express** REST API + **Socket.io** realtime
- **MongoDB** lưu trữ dữ liệu telemetry
- **AJV** validate JSON schema
- Endpoints: `POST /api/telemetry`, WebSocket events

---

## 🚀 Kết quả đạt được

| Hạng mục                       | Kết quả                         |
| ------------------------------ | ------------------------------- |
| Độ chính xác phát hiện va chạm | >95% (trên dữ liệu thực tế)     |
| Thời gian phản hồi             | <600ms từ va chạm đến cảnh báo  |
| GPS định vị                    | ~2.5m độ chính xác              |
| BLE range                      | ~10m trong nhà, ~30m ngoài trời |
| Telegram alert                 | <2 giây                         |
| Mô hình ML trên ESP32          | <10ms inference, ~5KB bộ nhớ    |

---

## 🔬 Hướng phát triển

- [ ] Tích hợp SIM 4G thay WiFi để hoạt động mọi nơi
- [ ] Camera AI nhận diện biển số xe gây tai nạn
- [ ] TinyML (TensorFlow Lite Micro) nâng cấp mô hình
- [ ] Cảm biến nhịp tim, oxy máu theo dõi sức khỏe
- [ ] Kết nối CSGT / 115 tự động

---

## 👨‍🎓 Tác giả

- **Họ tên**: Đào Văn Phong
- **Ngành**: Phân Tích Dữ Liệu
- **Trường**: Học Viện Công Nghệ Bưu Chính Viễn Thông
- **Năm**: 2026
