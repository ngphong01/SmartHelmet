import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/telemetry_data.dart';
import '../services/ble_service.dart';

class ImpactAlertScreen extends StatefulWidget {
  final TelemetryData data;
  final BleService bleService;
  const ImpactAlertScreen({
    super.key,
    required this.data,
    required this.bleService,
  });

  // 🔴 SỐ ĐIỆN THOẠI KHẨN CẤP - NGƯỜI THÂN
  static const emergencyPhone = '0868314386';

  @override
  State<ImpactAlertScreen> createState() => _ImpactAlertScreenState();
}

class _ImpactAlertScreenState extends State<ImpactAlertScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  int _countdown = 30;
  bool _done = false;
  Timer? _countdownTimer;
  Timer? _autoCallTimer;
  Timer? _autoSosTimer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    HapticFeedback.heavyImpact();

    // Đếm ngược hiển thị - dùng Timer thay vì Future.doWhile
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _done) {
        timer.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) timer.cancel();
    });

    // 🤕 TỰ ĐỘNG GỌI sau 15 giây nếu bất tỉnh
    _autoCallTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_done) _callEmergency();
    });

    // 🆘 Tự động SOS sau 30 giây
    _autoSosTimer = Timer(const Duration(seconds: 31), () {
      if (mounted && !_done) {
        widget.bleService.sendSos();
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _countdownTimer?.cancel();
    _autoCallTimer?.cancel();
    _autoSosTimer?.cancel();
    super.dispose();
  }

  void _ack() => _dismiss(() => widget.bleService.sendAck());
  void _sos() => _dismiss(() => widget.bleService.sendSos());
  void _dismiss(VoidCallback action) {
    setState(() => _done = true);
    action();
    Navigator.of(context).pop();
  }

  Future<void> _callEmergency() async {
    final uri = Uri.parse('tel:${ImpactAlertScreen.emergencyPhone}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể gọi điện'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final hasGps = d.hasGps;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0000), Color(0xFF0A0E21), Color(0xFF0A0E21)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, child) => Transform.scale(
                      scale: 1.0 + _pulse.value * 0.12,
                      child: child,
                    ),
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF4444), Color(0xFFCC0000)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF0000).withAlpha(100),
                            blurRadius: 40,
                            spreadRadius: 12,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('🚨', style: TextStyle(fontSize: 48)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'CẢNH BÁO VA CHẠM!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.red,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.red.withAlpha(80),
                        width: 1.5,
                      ),
                      gradient: LinearGradient(
                        colors: [
                          Colors.red.withAlpha(20),
                          Colors.red.withAlpha(5),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        _row(
                          '🧠 AI Xác Suất',
                          '${(d.impact!.aiP * 100).toStringAsFixed(1)}%',
                        ),
                        _row(
                          '⚡ Đỉnh Gia Tốc',
                          '${d.impact!.peakG.toStringAsFixed(2)} g',
                        ),
                        if (hasGps) ...[
                          const SizedBox(height: 8),
                          Container(height: 1, color: Colors.white10),
                          const SizedBox(height: 8),
                          _row('📍 Vĩ Độ', d.gps!.lat.toStringAsFixed(5)),
                          _row('📍 Kinh Độ', d.gps!.lon.toStringAsFixed(5)),
                          _row(
                            '🏍️ Tốc Độ',
                            '${d.gps!.speedKmh.toStringAsFixed(1)} km/h',
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '⏱ Tự động SOS sau $_countdown giây nếu không phản hồi',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: _btn(
                          'TÔI ỔN',
                          Icons.check_circle_rounded,
                          const Color(0xFF10B981),
                          _ack,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _btn(
                          'SOS',
                          Icons.warning_rounded,
                          Colors.red,
                          _sos,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 📞 Nút gọi khẩn cấp
                  _btnFull(
                    '📞 GỌI CỨU HỘ ${ImpactAlertScreen.emergencyPhone}',
                    const Color(0xFFFF6B35),
                    _callEmergency,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _btn(String label, IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withAlpha(120), width: 2),
            gradient: LinearGradient(
              colors: [color.withAlpha(35), color.withAlpha(10)],
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 38),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _btnFull(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withAlpha(120), width: 2),
            gradient: LinearGradient(
              colors: [color.withAlpha(35), color.withAlpha(10)],
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 1.5,
            ),
          ),
        ),
      );
}
