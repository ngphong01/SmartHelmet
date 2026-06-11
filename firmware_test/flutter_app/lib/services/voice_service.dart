import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;

  static Future<bool> init() async {
    if (_initialized) return true;

    try {
      final dynamic rawLangs = await _tts.getLanguages;
      final List<String> langs = List<String>.from(rawLangs ?? []);
      debugPrint('[TTS] Ngon ngu kha dung: $langs');

      bool viSet = false;
      for (final code in ['vi-VN', 'vi', 'vi_VN', 'vie']) {
        if (langs.contains(code)) {
          await _tts.setLanguage(code);
          viSet = true;
          debugPrint('[TTS] ✅ Da chon tieng Viet (code=$code)');
          break;
        }
      }
      if (!viSet) {
        debugPrint('[TTS] ⚠️ Khong co tieng Viet, dung ngon ngu mac dinh');
      }

      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _initialized = true;
      debugPrint('[TTS] ✅ Khoi tao xong');
      return true;
    } catch (e) {
      debugPrint('[TTS] ❌ Loi khoi tao: $e');
      return false;
    }
  }

  static Future<void> speak(String text) async {
    final ok = await init();
    if (!ok) {
      debugPrint('[TTS] ❌ Khong the phat voice - TTS chua san sang');
      return;
    }
    debugPrint('[TTS] 🔊 Dang phat: $text');
    await _tts.speak(text);
    debugPrint('[TTS] ✅ Phat xong');
  }

  static Future<void> stop() async {
    await _tts.stop();
    _initialized = false;
  }

  static Future<void> dispose() async {
    await stop();
  }

  static String buildVietnameseMessage({
    required double lat,
    required double lon,
    required double peakG,
    required double aiProbability,
  }) {
    return '''
Cảnh báo. Người đội mũ bảo hiểm có thể đã bị ngã.
Lực va chạm ${peakG.toStringAsFixed(1)} g. Xác suất ngã ${(aiProbability * 100).toStringAsFixed(0)} phần trăm.
Vị trí: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}.
Kiểm tra ngay.
''';
  }
}
