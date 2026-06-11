import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/telemetry_data.dart';
import '../services/ble_service.dart';
import '../utils/app_logger.dart';

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

  /// Có phải fall (ngã xe) không
  bool get _isFall => data.impact?.isFall == true;

  @override
  State<ImpactAlertScreen> createState() => _ImpactAlertScreenState();
}

class _ImpactAlertScreenState extends State<ImpactAlertScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  int _countdown = 30;
  bool _done = false;
  bool _holdingAck = false;
  double _holdProgress = 0.0;
  Timer? _countdownTimer;
  Timer? _autoCallTimer;
  Timer? _autoSosTimer;
  Timer? _holdTimer;
  Timer? _rumbleTimer;

  static const _callAfter = 15;
  static const _sosAfter = 30;
  static const _holdDur = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    HapticFeedback.heavyImpact();

    // Rung liên tục
    _rumbleTimer = Timer.periodic(const Duration(milliseconds: 800), (t) {
      if (!mounted || _done)
        t.cancel();
      else
        HapticFeedback.heavyImpact();
    });

    // Đếm ngược
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _done) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown == _callAfter) HapticFeedback.heavyImpact();
      });
      if (_countdown <= 0) t.cancel();
    });

    // Tự động gọi sau 15s
    _autoCallTimer = Timer(Duration(seconds: _callAfter), () {
      if (mounted && !_done) _callEmergency();
    });

    // Tự động SOS sau 30s
    _autoSosTimer = Timer(Duration(seconds: _sosAfter + 1), () {
      if (mounted && !_done) {
        widget.bleService.sendSos();
        Navigator.of(context).pop();
      }
    });

    logImpact(
      'ALERT',
      widget.data.impact?.isFall == true
          ? '🛑 FALL! pitch=${widget.data.imu?.pitchDeg.toStringAsFixed(1) ?? "?"}°'
          : '🚨 IMPACT! peak=${widget.data.impact?.peakG.toStringAsFixed(2) ?? "?"}g',
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _countdownTimer?.cancel();
    _autoCallTimer?.cancel();
    _autoSosTimer?.cancel();
    _holdTimer?.cancel();
    _rumbleTimer?.cancel();
    super.dispose();
  }

  void _onHoldStart(LongPressStartDetails _) {
    setState(() {
      _holdingAck = true;
      _holdProgress = 0.0;
    });
    HapticFeedback.mediumImpact();
    final start = DateTime.now();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final p =
          (DateTime.now().difference(start).inMilliseconds /
                  _holdDur.inMilliseconds)
              .clamp(0.0, 1.0);
      setState(() => _holdProgress = p);
      if (p >= 1.0) {
        t.cancel();
        _ack();
      }
    });
  }

  void _onHoldEnd(LongPressEndDetails _) {
    _holdTimer?.cancel();
    setState(() {
      _holdingAck = false;
      _holdProgress = 0.0;
    });
  }

  void _onHoldCancel() {
    _holdTimer?.cancel();
    setState(() {
      _holdingAck = false;
      _holdProgress = 0.0;
    });
  }

  void _ack() {
    final elapsed = _sosAfter - _countdown;
    logInfo('UI', '👍 User giu TOI ON (sau ${elapsed}s)');
    incrementAck();
    _done = true;
    widget.bleService.sendAck();
    Navigator.of(context).pop();
  }

  void _sos() {
    logWarn('UI', '🆘 User TAP SOS!');
    incrementSos();
    _done = true;
    widget.bleService.sendSos();
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
    final urgent = _countdown <= _callAfter;
    final callP = 1.0 - (_countdown / _sosAfter);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: urgent
                    ? [
                        const Color(0xFF330000),
                        const Color(0xFF1A0000),
                        const Color(0xFF0A0E21),
                      ]
                    : [
                        const Color(0xFF1A0000),
                        const Color(0xFF0A0E21),
                        const Color(0xFF0A0E21),
                      ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Spacer(flex: 1),
                    // Icon pulse
                    Transform.scale(
                      scale: 1.0 + _pulse.value * 0.15,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF4444), Color(0xFFCC0000)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFFF0000,
                              ).withAlpha(urgent ? 180 : 100),
                              blurRadius: urgent ? 60 : 40,
                              spreadRadius: urgent ? 16 : 8,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget._isFall ? '🛑' : '🚨',
                            style: const TextStyle(fontSize: 44),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Title
                    Text(
                      widget._isFall
                          ? 'PHÁT HIỆN NGÃ XE!'
                          : 'CẢNH BÁO VA CHẠM!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.red,
                        letterSpacing: 2,
                      ),
                    ),
                    if (widget._isFall)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Mũ nghiêng > 55° — có thể bạn đã ngã!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Countdown ring
                    SizedBox(
                      width: 130,
                      height: 130,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 130,
                            height: 130,
                            child: CircularProgressIndicator(
                              value: callP,
                              strokeWidth: 8,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                urgent ? Colors.red : const Color(0xFFFF6B35),
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$_countdown',
                                style: TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900,
                                  color: urgent ? Colors.red : Colors.white,
                                ),
                              ),
                              const Text(
                                'giây',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      urgent
                          ? '⏱ Tự động gọi cứu hộ!'
                          : 'Tự động SOS sau $_countdown giây',
                      style: TextStyle(
                        color: urgent ? Colors.redAccent : Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Info cards
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.withAlpha(60)),
                        color: Colors.red.withAlpha(15),
                      ),
                      child: Column(
                        children: [
                          _infoRow(
                            '⚡ Peak G',
                            '${d.impact?.peakG.toStringAsFixed(2) ?? "?"} g',
                          ),
                          _infoRow(
                            '🧠 AI',
                            '${((d.impact?.aiP ?? 0) * 100).toStringAsFixed(1)}%',
                          ),
                          if (widget._isFall) ...[
                            _infoRow(
                              '📐 Pitch',
                              '${d.imu?.pitchDeg.toStringAsFixed(1) ?? "?"}°',
                            ),
                            _infoRow(
                              '📐 Roll',
                              '${d.imu?.rollDeg.toStringAsFixed(1) ?? "?"}°',
                            ),
                          ],
                          if (hasGps) ...[
                            const SizedBox(height: 6),
                            Container(height: 1, color: Colors.white10),
                            const SizedBox(height: 6),
                            _infoRow('📍 Vĩ độ', d.gps!.lat.toStringAsFixed(5)),
                            _infoRow(
                              '📍 Kinh độ',
                              d.gps!.lon.toStringAsFixed(5),
                            ),
                            _infoRow(
                              '🏍️ Tốc độ',
                              '${d.gps!.speedKmh.toStringAsFixed(1)} km/h',
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(flex: 2),
                    // HOLD TO CONFIRM
                    GestureDetector(
                      onLongPressStart: _onHoldStart,
                      onLongPressEnd: _onHoldEnd,
                      onLongPressCancel: _onHoldCancel,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: double.infinity,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: _holdingAck
                                ? [
                                    const Color(0xFF34D399),
                                    const Color(0xFF059669),
                                  ]
                                : [
                                    const Color(0xFF10B981),
                                    const Color(0xFF047857),
                                  ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF10B981,
                              ).withAlpha(_holdingAck ? 180 : 80),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_holdingAck)
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      width:
                                          MediaQuery.of(context).size.width *
                                          _holdProgress,
                                      color: Colors.white.withAlpha(30),
                                    ),
                                  ),
                                ),
                              ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                  size: 36,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _holdingAck
                                      ? '${(_holdProgress * 100).toInt()}% — GIỮ TIẾP...'
                                      : 'TÔI ỔN',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                                if (!_holdingAck)
                                  const Text(
                                    '(giữ 2 giây)',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // SOS + Call row
                    Row(
                      children: [
                        Expanded(child: _smallBtn('🆘 SOS', Colors.red, _sos)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _smallBtn(
                            '📞 ${ImpactAlertScreen.emergencyPhone}',
                            const Color(0xFFFF6B35),
                            _callEmergency,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(
          v,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _smallBtn(String label, Color color, VoidCallback onTap) => SizedBox(
    height: 50,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
