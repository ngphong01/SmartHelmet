# TESTING.md — Test Plan cho Hệ thống Mũ Bảo Hiểm Thông Minh

## Mục tiêu

Xác minh hệ thống hoạt động ổn định, không false positive khi đi xe bình thường,
và phát hiện chính xác các tình huống va chạm / ngã xe.

---

## 1. ESP32 Firmware Tests

### 1.1. Impact Detection

| Test Case                 | Điều kiện                           | Kết quả mong đợi       |
| ------------------------- | ----------------------------------- | ---------------------- |
| Đi xe bình thường 30 phút | Tốc độ 20-40 km/h, đường bằng phẳng | 0 false positive       |
| Phanh gấp 10 lần          | Giảm tốc đột ngột từ 30→0 km/h      | 0 false positive       |
| Qua ổ gà 20 lần           | Đường xấu, rung lắc mạnh            | 0 false positive       |
| Mô phỏng va chạm 10 lần   | Đập mũ vào đệm/gối với lực vừa      | 10/10 phát hiện impact |
| Mô phỏng ngã xe 5 lần     | Đổ mũ nghiêng > 60° + lắc mạnh      | 5/5 phát hiện fall     |

### 1.2. BLE Connectivity

| Test Case                      | Kết quả mong đợi                         |
| ------------------------------ | ---------------------------------------- |
| Kết nối BLE lần đầu            | Phone 1 kết nối < 5s, hiện "SmartHelmet" |
| Kết nối phone thứ 2            | Cả 2 phone kết nối đồng thời             |
| Mất kết nối BLE (tắt BT phone) | ESP32 auto-restart advertising < 2s      |
| Reconnect sau mất kết nối      | Phone reconnect < 10s, nhận lại dữ liệu  |
| Heartbeat hoạt động            | PING/PONG mỗi 5s, timeout 15s            |

### 1.3. WiFi + Telegram

| Test Case                    | Kết quả mong đợi                  |
| ---------------------------- | --------------------------------- |
| WiFi có sẵn → Telegram alert | Gửi thành công < 3s sau impact    |
| Không WiFi → cache alert     | Lưu vào buffer, retry khi có WiFi |
| Multi-SSID switching         | Tự động chọn WiFi mạnh nhất       |

### 1.4. GPS

| Test Case      | Kết quả mong đợi             |
| -------------- | ---------------------------- |
| GPS ngoài trời | Fix < 3 phút, satellites ≥ 4 |
| GPS trong nhà  | Dùng cache vị trí cuối cùng  |
| GPS cache age  | Hiển thị "X phút trước"      |

### 1.5. State Machine

| Test Case                         | Kết quả mong đợi                   |
| --------------------------------- | ---------------------------------- |
| Đứng yên → IDLE                   | State = IDLE, không chạy detection |
| Tốc độ > 8 km/h trong 5s → RIDING | State = RIDING, chạy detection     |
| Impact khi RIDING → IMPACT        | State = IMPACT, gửi cảnh báo       |
| Impact + tilt > 55° → FALLEN      | State = FALLEN, gửi fall alert     |
| Đứng yên 5 phút → IDLE            | Tự động về IDLE                    |

---

## 2. App Flutter Tests

### 2.1. Foreground Service

| Test Case                   | Kết quả mong đợi                 |
| --------------------------- | -------------------------------- |
| App chạy nền (màn hình tắt) | Vẫn nhận BLE data, không bị kill |
| Notification hiển thị       | "Mũ thông minh đang hoạt động"   |
| Pin điện thoại              | Tiêu thụ < 5%/giờ khi chạy nền   |

### 2.2. Auto-reconnect

| Test Case                     | Kết quả mong đợi       |
| ----------------------------- | ---------------------- |
| Đi xa khỏi mũ > 10m → mất BLE | App hiện "Mất kết nối" |
| Quay lại gần mũ               | Auto-reconnect < 10s   |
| Tắt/Bật BT trên phone         | Reconnect tự động      |

### 2.3. GPS Fallback

| Test Case                        | Kết quả mong đợi                  |
| -------------------------------- | --------------------------------- |
| NEO-6M có fix                    | Dùng GPS mũ (icon 🛰️)             |
| NEO-6M mất fix > 10s             | Fallback sang Phone GPS (icon 📱) |
| Demo trong nhà (không satellite) | Dùng Phone GPS, vẫn track được    |

### 2.4. UI/UX

| Test Case                      | Kết quả mong đợi            |
| ------------------------------ | --------------------------- |
| Nút "TÔI ỔN" to, dễ bấm        | Chiếm ≥ 40% màn hình        |
| Rung + âm thanh khi cảnh báo   | Haptic mạnh + alarm sound   |
| Đếm ngược 30s                  | Số + progress bar rõ ràng   |
| Hết 30s không bấm → gửi cứu hộ | Telegram + backend nhận SOS |

---

## 3. Backend Tests

### 3.1. Web Dashboard

| Test Case                       | Kết quả mong đợi                   |
| ------------------------------- | ---------------------------------- |
| Map realtime hiển thị vị trí mũ | Marker di chuyển mượt, update ≤ 2s |
| Trạng thái Online/Offline       | Dựa trên heartbeat                 |
| Cảnh báo hiển thị popup         | Khi có impact → popup đỏ + rung    |
| Multi-helmet                    | Dropdown chọn mũ hoạt động         |

---

## 4. Kết quả kiểm thử

Điền kết quả thực tế vào bảng sau khi test:

| Ngày | Test Case | Kết quả | Ghi chú |
| ---- | --------- | ------- | ------- |
|      |           | ✅/❌   |         |
|      |           |         |         |
|      |           |         |         |

---

## 5. Tổng kết

- [ ] Tất cả test case đều PASS
- [ ] False positive rate < 1%
- [ ] Impact detection rate > 95%
- [ ] BLE reconnect < 10s
- [ ] Telegram alert < 5s
- [ ] App foreground service ổn định > 1 giờ
