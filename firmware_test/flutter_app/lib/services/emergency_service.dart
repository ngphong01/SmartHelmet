import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/services.dart';

/// Dịch vụ gọi điện khẩn cấp và gửi thông báo
class EmergencyService {
  /// Gọi điện tới số khẩn cấp
  static Future<bool> call(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }

  /// Gọi điện trực tiếp (CALL intent - Android)
  static Future<bool> callDirect(String phoneNumber) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.CALL',
        data: 'tel:$phoneNumber',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return true;
    } catch (e) {
      // Fallback: mở dialer
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.DIAL',
          data: 'tel:$phoneNumber',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  static const _channel = MethodChannel('smart_helmet/telephony');

  /// Kiểm tra SIM có thật sự hoạt động không
  /// Dùng TelephonyManager.getSimState() — chính xác cả khi không lắp SIM
  static Future<bool> canMakePhoneCall() async {
    try {
      final simState = await _channel.invokeMethod<int>('getSimState');
      // SIM_STATE_READY = 5 → có SIM hoạt động
      // SIM_STATE_ABSENT = 1 → không lắp SIM
      // SIM_STATE_PIN_REQUIRED = 2, SIM_STATE_PUK_REQUIRED = 3, v.v.
      final hasSim = (simState != null && simState == 5);
      if (!hasSim) return false;

      final uri = Uri(scheme: 'tel', path: '000');
      return await canLaunchUrl(uri);
    } catch (_) {
      try {
        final uri = Uri(scheme: 'tel', path: '000');
        return await canLaunchUrl(uri);
      } catch (_) {
        return false;
      }
    }
  }

  /// Gọi 115 (cấp cứu) - giữ lại để dùng sau nếu cần
  static Future<bool> call115() async {
    return callDirect('115');
  }

  /// Gửi SMS (nếu có SIM)
  static Future<bool> sendSms(String phoneNumber, String message) async {
    final uri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: {'body': message},
    );
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }

  /// Mở Google Maps với vị trí hiện tại
  static Future<bool> openGoogleMaps(double lat, double lon) async {
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri);
    }
    return false;
  }

  /// Tạo tin nhắn SOS
  static String buildSosMessage({
    required double lat,
    required double lon,
    required double peakG,
    required double aiProbability,
  }) {
    return '''
🆘 SOS! NGƯỜI ĐỘI MŨ BỊ NGÃ!

📍 Vị trí: $lat, $lon
🗺 Maps: https://www.google.com/maps/search/?api=1&query=$lat,$lon
💥 Đỉnh gia tốc: ${peakG.toStringAsFixed(1)}g
🧠 AI xác suất ngã: ${(aiProbability * 100).toStringAsFixed(0)}%

Vui lòng kiểm tra ngay! Đây là tin nhắn tự động từ Smart Helmet.
''';
  }
}
