import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/emergency_service.dart';
import '../services/voice_service.dart';

enum AlertPhase { countdown, calling, smsSent, callingRelative2, done }

class FallAlertScreen extends StatefulWidget {
  final double latitude, longitude, peakG, aiProbability;
  final String emergencyPhone;
  final String emergencyPhone2; // số người thân thứ 2 (fallback)
  final VoidCallback onAck, onSos;

  const FallAlertScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.peakG,
    required this.aiProbability,
    required this.emergencyPhone,
    required this.emergencyPhone2,
    required this.onAck,
    required this.onSos,
  });

  @override
  State<FallAlertScreen> createState() => _FallAlertScreenState();
}

class _FallAlertScreenState extends State<FallAlertScreen>
    with TickerProviderStateMixin {
  static const int CD = 30; // đếm ngược ban đầu

  int _count = CD;
  Timer? _timer;
  bool _called = false;
  bool _stopped = false;
  bool _calledRel2 = false;
  bool _playerDisposed = false;
  bool _simAvailable = true;
  AlertPhase _phase = AlertPhase.countdown;
  final _player = AudioPlayer();

  late AnimationController _pulse;
  late AnimationController _shake;
  late AnimationController _ring;
  late Animation<double> _pulseAnim;
  late Animation<double> _ringAnim;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    _pulse = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this)
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.2, end: 1.0)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    _shake = AnimationController(
        duration: const Duration(milliseconds: 80), vsync: this)
      ..repeat(reverse: true);

    _ring = AnimationController(
        duration: const Duration(milliseconds: 1200), vsync: this)
      ..repeat();
    _ringAnim = Tween(begin: 0.8, end: 1.2)
        .animate(CurvedAnimation(parent: _ring, curve: Curves.easeInOut));

    _startAlarm();
  }

  void _startAlarm() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('sounds/alarm.wav'));
    } catch (_) {}

    final hasVib = await Vibration.hasVibrator();
    if (hasVib == true) Vibration.vibrate(pattern: [1000, 400], repeat: 0);

    // Kiểm tra SIM
    _simAvailable = await EmergencyService.canMakePhoneCall();
    debugPrint('[SOS] SIM available: $_simAvailable');

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _stopped) {
        t.cancel();
        return;
      }
      if (_count > 0) {
        setState(() => _count--);
      }
      if (_count <= 0) {
        t.cancel();
        _call();
      }
    });
  }

  void _stopSoundAndVibration() {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    Vibration.cancel();
    WakelockPlus.disable();
    if (!_playerDisposed) {
      _playerDisposed = true;
      _player.stop();
      _player.dispose();
    }
  }

  void _stopAll() {
    _stopSoundAndVibration();
    _pulse.stop();
    _shake.stop();
    _ring.stop();
  }

  // ═══════════════════════════════════════════════════════════
  // CHUỖI KHẨN CẤP: Gọi người 1 → Gọi người 2 → Voice TTS
  // ═══════════════════════════════════════════════════════════

  Future<void> _call() async {
    if (_called) return;
    _called = true;
    _stopSoundAndVibration();
    if (!mounted) return;
    setState(() => _phase = AlertPhase.calling);

    final phonePerm = await Permission.phone.status;
    if (phonePerm.isDenied) {
      await Permission.phone.request();
    }

    if (_simAvailable) {
      // Bước 1: Gọi người thân 1
      debugPrint('[SOS] 🔴 Buoc 1: Goi nguoi than 1: ${widget.emergencyPhone}');
      final ok = await EmergencyService.callDirect(widget.emergencyPhone);
      debugPrint(
          '[SOS] Goi ${ok ? "thanh cong" : "that bai, fallback dialer"}');
    } else {
      debugPrint('[SOS] ⚠️ SIM khong kha dung — bo qua goi, chuyen sang voice');
    }
    widget.onSos();

    if (!mounted) return;

    // Test voice: gọi xong người 1 → TTS luôn
    _speakAndGoHome();
  }

  Future<void> _callRel2AndFinish() async {
    if (_calledRel2) return;
    _calledRel2 = true;
    if (!mounted) return;
    setState(() => _phase = AlertPhase.callingRelative2);

    if (_simAvailable) {
      // Bước 2: Gọi người thân 2
      debugPrint(
          '[SOS] 📞 Buoc 2: Goi nguoi than 2: ${widget.emergencyPhone2}');
      await EmergencyService.callDirect(widget.emergencyPhone2);
    } else {
      debugPrint('[SOS] ⚠️ Bo qua goi nguoi than 2 — SIM khong kha dung');
    }

    if (!mounted) return;
    setState(() => _phase = AlertPhase.done);

    // Phát voice TTS ngay lập tức sau khi gọi người 2 xong
    _speakAndGoHome();
  }

  Future<void> _speakAndGoHome() async {
    try {
      final voiceMsg = VoiceService.buildVietnameseMessage(
        lat: widget.latitude,
        lon: widget.longitude,
        peakG: widget.peakG,
        aiProbability: widget.aiProbability,
      );
      debugPrint('[SOS] 🔊 Phat voice TTS: $voiceMsg');
      await VoiceService.speak(voiceMsg);
      debugPrint('[SOS] ✅ Voice TTS hoan tat');
    } catch (e) {
      debugPrint('[SOS] ❌ Voice TTS loi: $e');
    }
    _goHome();
  }

  void _goHome() {
    _stopAll();
    widget.onAck();
  }

  @override
  void dispose() {
    _stopSoundAndVibration();
    _pulse.dispose();
    _shake.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  const Color(0xFFFF1744)
                      .withAlpha((_pulseAnim.value * 180).toInt()),
                  const Color(0xFFFF1744)
                      .withAlpha((_pulseAnim.value * 60).toInt()),
                  const Color(0xFF0A0A0A),
                ],
              ),
            ),
            child: SafeArea(child: child!),
          ),
          child: AnimatedBuilder(
            animation: _shake,
            builder: (_, child) => Transform.translate(
              offset: Offset(math.sin(_shake.value * math.pi * 16) * 3,
                  math.cos(_shake.value * math.pi * 14) * 2),
              child: child!,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 30),
                  // ⚠️ ICON
                  AnimatedBuilder(
                    animation: _ringAnim,
                    builder: (_, child) =>
                        Transform.scale(scale: _ringAnim.value, child: child!),
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.red.withAlpha(120), width: 4),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.red.withAlpha(80),
                              blurRadius: 40,
                              spreadRadius: 10)
                        ],
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          size: 60, color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // TIÊU ĐỀ
                  Text(
                    _count > 0 ? '⚠️ PHÁT HIỆN NGÃ' : '🆘 ĐANG GỌI CỨU HỘ',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 6),
                  if (!_simAvailable && _count <= 0)
                    const Text('⚠️ SIM không khả dụng — không thể gọi/SMS',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFFFF9100))),
                  Text(
                    _phase == AlertPhase.calling
                        ? '📞 ${widget.emergencyPhone}'
                        : _phase == AlertPhase.smsSent
                            ? '📩 Đã gửi SMS'
                            : _phase == AlertPhase.callingRelative2
                                ? '📞 ${widget.emergencyPhone2}'
                                : _count > 0
                                    ? 'Có thể bạn đã bị ngã xe'
                                    : 'Đang thực hiện cuộc gọi...',
                    style:
                        const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
                  ),
                  const SizedBox(height: 28),

                  // INFO CARDS
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.white.withAlpha(10),
                        border: Border.all(color: Colors.white.withAlpha(15)),
                      ),
                      child: Column(children: [
                        _row(
                            '🧠 AI xác suất',
                            '${(widget.aiProbability * 100).toStringAsFixed(1)}%',
                            const Color(0xFFFF9100)),
                        const Divider(color: Color(0xFF2C2C2E), height: 20),
                        _row(
                            '💥 Đỉnh gia tốc',
                            '${widget.peakG.toStringAsFixed(1)}g',
                            const Color(0xFFFF1744)),
                        if (widget.latitude != 0) ...[
                          const Divider(color: Color(0xFF2C2C2E), height: 20),
                          _row(
                              '📍 GPS',
                              '${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}',
                              const Color(0xFF00D4FF)),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ⏱ ĐẾM NGƯỢC
                  if (_count > 0) ...[
                    const Text('Tự động gọi cứu hộ sau',
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                    const SizedBox(height: 6),
                    Text(
                      '$_count',
                      style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.w200,
                          color: _count <= 10
                              ? Colors.red
                              : const Color(0xFFFF9100),
                          height: 1,
                          letterSpacing: -4),
                    ),
                    const Text('GIÂY',
                        style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF8E8E93),
                            letterSpacing: 2)),
                  ],

                  const SizedBox(height: 28),

                  // ✅ NÚT TÔI ỔN
                  if (_count > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            VoiceService.stop();
                            _stopAll();
                            widget.onAck();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                            elevation: 0,
                          ),
                          child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, size: 26),
                                SizedBox(width: 10),
                                Text('TÔI ỔN - HỦY CẢNH BÁO',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800)),
                              ]),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // 📞 GỌI NGAY
                  if (_count > 0)
                    TextButton.icon(
                      onPressed: _call,
                      icon: const Icon(Icons.call, color: Colors.red, size: 20),
                      label: Text('GỌI NGAY ${widget.emergencyPhone}',
                          style: const TextStyle(
                              color: Colors.red,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label,
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
      Text(value,
          style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }
}
