#include "telegram.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <UniversalTelegramBot.h>
#include <ArduinoJson.h>
#include "secrets.h"
#include "wifi_manager.h"

static WiFiClientSecure gWifiClient;
static UniversalTelegramBot *gBot = nullptr;

// =========================
// KHỞI TẠO
// =========================

void telegram_init()
{
    // Cấu hình WiFi Client bảo mật (bỏ qua xác thực chứng chỉ cho Telegram)
    gWifiClient.setInsecure();

    // Dùng wifi_manager để kiểm tra kết nối (không tự ý WiFi.begin nữa)
    if (wifi_manager_is_connected())
    {
        gBot = new UniversalTelegramBot(TELEGRAM_BOT_TOKEN, gWifiClient);
        Serial.println("[Telegram][OK] Bot da san sang");

        // Gửi tin nhắn khởi động
        telegram_send_message("🟢 *MU BAO HIEM THONG MINH*\nHe thong da khoi dong.\nSan sang phat hien va cham.");
    }
    else
    {
        Serial.println("[Telegram][LOI] Bot chua san sang (chua co WiFi). Se tu dong kich hoat khi co WiFi.");
    }
}

// =========================
// GỬI TIN NHẮN
// =========================

bool telegram_send_message(const char *message)
{
    // Khởi tạo bot nếu chưa có nhưng WiFi đã sẵn sàng
    if (!gBot && wifi_manager_is_connected())
    {
        gBot = new UniversalTelegramBot(TELEGRAM_BOT_TOKEN, gWifiClient);
        Serial.println("[Telegram][OK] Bot da san sang (lazy init)");
    }

    if (!gBot)
    {
        return false; // không log spam
    }

    // Kiểm tra WiFi qua wifi_manager
    if (!wifi_manager_is_connected())
    {
        return false;
    }

    bool ok = gBot->sendMessage(TELEGRAM_CHAT_ID, message, "Markdown");
    if (ok)
    {
        Serial.println("[Telegram][OK] Da gui tin nhan");
    }
    else
    {
        Serial.println("[Telegram][LOI] Gui tin nhan that bai");
    }
    return ok;
}

// =========================
// GỬI CẢNH BÁO VA CHẠM
// =========================

void telegram_send_impact_alert(float lat, float lon, float speed_kmh,
                                float ai_probability, float peak_g,
                                bool gps_valid)
{
    char msg[512];

    if (gps_valid)
    {
        snprintf(msg, sizeof(msg),
                 "🚨 *CANH BAO VA CHAM!*\n\n"
                 "📍 *Vi tri GPS:*\n"
                 "   Lat: %.6f\n"
                 "   Lon: %.6f\n"
                 "   Toc do: %.1f km/h\n\n"
                 "📊 *Du lieu va cham:*\n"
                 "   AI xac suat: %.1f%%\n"
                 "   Dinh gia toc: %.2fg\n\n"
                 "🗺 [Xem tren Google Maps](https://maps.google.com/?q=%.6f,%.6f)\n\n"
                 "⚠️ *CAN KIEM TRA NGAY!*",
                 lat, lon, speed_kmh,
                 ai_probability * 100.0f, peak_g,
                 lat, lon);
    }
    else
    {
        snprintf(msg, sizeof(msg),
                 "🚨 *CANH BAO VA CHAM!*\n\n"
                 "📍 *Vi tri GPS:* CHUA CO TOA DO\n\n"
                 "📊 *Du lieu va cham:*\n"
                 "   AI xac suat: %.1f%%\n"
                 "   Dinh gia toc: %.2fg\n\n"
                 "⚠️ *CAN KIEM TRA NGAY!*",
                 ai_probability * 100.0f, peak_g);
    }

    telegram_send_message(msg);
}

// =========================
// LOOP (xử lý tin nhắn đến nếu cần)
// =========================

void telegram_loop()
{
    // Có thể dùng để kiểm tra tin nhắn đến từ Telegram
    // Hiện tại để trống, sau này có thể thêm lệnh điều khiển từ xa
}
