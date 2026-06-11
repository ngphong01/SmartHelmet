import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../models/telemetry_data.dart';
import 'impact_alert_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

// ═══════════════════════════════════════════════════════════
class AppColors {
  static const bg = Color(0xFF0A0E14);
  static const surface = Color(0xFF141920);
  static const surfaceLight = Color(0xFF1C2330);
  static const accent = Color(0xFF00D4FF);
  static const accent2 = Color(0xFF7C3AED);
  static const green = Color(0xFF00E676);
  static const orange = Color(0xFFFF9100);
  static const red = Color(0xFFFF1744);
  static const textDim = Color(0xFF6B7280);
  static const cardBorder = Color(0xFF252A35);
}

// ═══════════════════════════════════════════════════════════
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (_, ble, __) =>
          ble.isConnected ? _DashboardView() : _ConnectView(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CONNECT SCREEN
// ═══════════════════════════════════════════════════════════
class _ConnectView extends StatefulWidget {
  const _ConnectView();
  @override
  State<_ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<_ConnectView>
    with TickerProviderStateMixin {
  bool _bluetoothOn = false;
  String _statusText = 'Đang kiểm tra Bluetooth...';
  String _statusDetail = '';

  late AnimationController _scanPulse, _helmetFloat, _dot1, _dot2, _dot3;
  late Animation<double> _pulseAnim, _floatAnim;

  @override
  void initState() {
    super.initState();
    _scanPulse = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scanPulse, curve: Curves.easeInOut));
    _helmetFloat = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _floatAnim = Tween(
      begin: -8.0,
      end: 8.0,
    ).animate(CurvedAnimation(parent: _helmetFloat, curve: Curves.easeInOut));
    _dot1 = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _dot2 = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _dot3 = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
    _checkBluetooth();
  }

  @override
  void dispose() {
    _scanPulse.dispose();
    _helmetFloat.dispose();
    _dot1.dispose();
    _dot2.dispose();
    _dot3.dispose();
    super.dispose();
  }

  Future<void> _checkBluetooth() async {
    final s = await FlutterBluePlus.adapterState.first;
    setState(() {
      _bluetoothOn = s == BluetoothAdapterState.on;
      _statusText = _bluetoothOn ? 'Sẵn sàng kết nối' : 'Bluetooth đang tắt';
      _statusDetail = _bluetoothOn
          ? 'Bật mũ bảo hiểm và nhấn nút bên dưới'
          : 'Vui lòng bật Bluetooth để tiếp tục';
    });
    FlutterBluePlus.adapterState.listen((s) {
      if (!mounted) return;
      setState(() {
        _bluetoothOn = s == BluetoothAdapterState.on;
        if (!_bluetoothOn) {
          _statusText = 'Bluetooth đang tắt';
          _statusDetail = 'Vui lòng bật Bluetooth để tiếp tục';
        }
      });
    });
  }

  Future<void> _connect() async {
    if (!_bluetoothOn) return;
    setState(() {
      _statusText = 'Đang tìm mũ...';
      _statusDetail = 'Đảm bảo mũ đã được bật nguồn';
    });
    try {
      await context.read<BleService>().connect();
    } catch (_) {
      if (mounted)
        setState(() {
          _statusText = 'Không tìm thấy mũ';
          _statusDetail = 'Thử lại hoặc kiểm tra mũ đã bật chưa';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BleService>().state;
    final scanning =
        state == BleConnectionState.scanning ||
        state == BleConnectionState.connecting;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            _helmet(scanning),
            const Spacer(flex: 1),
            const Text(
              'SMART HELMET',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mũ bảo hiểm thông minh',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textDim,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            _status(scanning),
            const SizedBox(height: 32),
            _btnConnect(scanning),
            const Spacer(flex: 2),
            Text(
              'phiên bản 2.0.0',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textDim.withAlpha(100),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _helmet(bool scanning) => AnimatedBuilder(
    animation: _floatAnim,
    builder: (_, child) =>
        Transform.translate(offset: Offset(0, _floatAnim.value), child: child!),
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (scanning) ...[
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 200 * _pulseAnim.value,
              height: 200 * _pulseAnim.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withAlpha(
                    (_pulseAnim.value * 80).toInt(),
                  ),
                  width: 2,
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 260 * (1 - _pulseAnim.value * 0.5),
              height: 260 * (1 - _pulseAnim.value * 0.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withAlpha(
                    (_pulseAnim.value * 40).toInt(),
                  ),
                  width: 1,
                ),
              ),
            ),
          ),
        ],
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.accent.withAlpha(30),
                AppColors.accent2.withAlpha(50),
              ],
            ),
            border: Border.all(
              color: scanning
                  ? AppColors.accent.withAlpha(150)
                  : AppColors.accent.withAlpha(60),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: (scanning ? AppColors.accent : AppColors.accent2)
                    .withAlpha(50),
                blurRadius: 40,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Icon(
            Icons.shield,
            size: 70,
            color: AppColors.accent.withAlpha(scanning ? 220 : 150),
          ),
        ),
        Positioned(
          top: 18,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scanning ? AppColors.accent : AppColors.textDim,
              boxShadow: scanning
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withAlpha(180),
                        blurRadius: 12,
                        spreadRadius: 3,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _status(bool scanning) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _statusText,
            key: ValueKey(_statusText),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scanning
                  ? AppColors.accent
                  : _bluetoothOn
                  ? AppColors.textDim
                  : AppColors.orange,
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _statusDetail,
          style: const TextStyle(fontSize: 13, color: AppColors.textDim),
          textAlign: TextAlign.center,
        ),
        if (scanning) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dot(_dot1, 0),
              const SizedBox(width: 8),
              _dot(_dot2, 300),
              const SizedBox(width: 8),
              _dot(_dot3, 600),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _dot(AnimationController c, int d) => AnimatedBuilder(
    animation: c,
    builder: (_, __) {
      double t = ((c.value * 1200 + d) % 1200) / 1200;
      return Opacity(
        opacity: t < 0.5 ? t * 2 : (1 - t) * 2,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
          ),
        ),
      );
    },
  );

  Widget _btnConnect(bool scanning) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 50),
    child: GestureDetector(
      onTap: _bluetoothOn && !scanning ? _connect : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: scanning
                ? [
                    AppColors.accent.withAlpha(100),
                    AppColors.accent2.withAlpha(100),
                  ]
                : _bluetoothOn
                ? [AppColors.accent, AppColors.accent2]
                : [
                    AppColors.textDim.withAlpha(80),
                    AppColors.textDim.withAlpha(40),
                  ],
          ),
          boxShadow: scanning
              ? [
                  BoxShadow(
                    color: AppColors.accent.withAlpha(60),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : _bluetoothOn
              ? [
                  BoxShadow(
                    color: AppColors.accent2.withAlpha(80),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Center(
          child: scanning
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'ĐANG TÌM...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _bluetoothOn
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _bluetoothOn ? 'KẾT NỐI VỚI MŨ' : 'BẬT BLUETOOTH',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════
class _DashboardView extends StatefulWidget {
  const _DashboardView();
  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulse;
  double _pitch = 0, _roll = 0, _lat = 0, _lon = 0, _speed = 0;
  int _sats = 0;
  String _ride = 'IDLE';

  BleService get _ble => context.read<BleService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _ble.addListener(_onData);
  }

  void _onData() {
    if (!mounted) return;
    final d = _ble.latestData;
    if (d == null) return;
    setState(() {
      _ride = d.state?.rideState ?? 'IDLE';
      _pitch = d.imu?.pitchDeg ?? 0;
      _roll = d.imu?.rollDeg ?? 0;
      _lat = d.gps?.lat ?? 0;
      _lon = d.gps?.lon ?? 0;
      _speed = d.gps?.speedKmh ?? 0;
      _sats = d.gps?.satellites ?? 0;
    });
    if (d.isImpact && d.impact?.isFall == true) _showFall(d);
  }

  void _showFall(TelemetryData d) {
    Navigator.of(context).push(
      PageRouteBuilder(
        fullscreenDialog: true,
        pageBuilder: (_, __, ___) =>
            ImpactAlertScreen(data: d, bleService: _ble),
        transitionsBuilder: (_, a, __, c) =>
            FadeTransition(opacity: a, child: c),
      ),
    );
  }

  @override
  void dispose() {
    _ble.removeListener(_onData);
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && !_ble.isConnected) _ble.connect();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    body: SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            _header(),
            const SizedBox(height: 16),
            _speedCard(),
            const SizedBox(height: 16),
            _tiltRow(),
            const SizedBox(height: 16),
            _helmet3D(),
            const SizedBox(height: 16),
            _gpsCard(),
            const SizedBox(height: 16),
            _actions(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.surfaceLight, AppColors.surface, AppColors.bg],
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🪖 Smart Helmet',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.green,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.green.withAlpha(
                            (_pulse.value * 150).toInt(),
                          ),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Đã kết nối',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            GestureDetector(
              onTap: () => _ble.sendCommand('SOS'),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.red, Color(0xFFD50000)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.red.withAlpha(80),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.sos, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.settings,
                color: AppColors.textDim,
                size: 22,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.history,
                color: AppColors.textDim,
                size: 22,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _speedCard() => _card([
    Row(
      children: [
        _iconBox(Icons.speed, AppColors.accent),
        const SizedBox(width: 10),
        const Text(
          'TỐC ĐỘ',
          style: TextStyle(
            color: AppColors.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const Spacer(),
        _rideBadge(),
      ],
    ),
    const SizedBox(height: 12),
    Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _speed.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 60,
            fontWeight: FontWeight.w200,
            color: Colors.white,
            height: 1,
            letterSpacing: -3,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            'km/h',
            style: TextStyle(fontSize: 15, color: AppColors.textDim),
          ),
        ),
        const Spacer(),
        Column(
          children: [
            Icon(
              Icons.satellite_alt,
              color: _sats > 0 ? AppColors.accent : AppColors.textDim,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              '$_sats',
              style: TextStyle(
                color: _sats > 0 ? AppColors.accent : AppColors.textDim,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    ),
    const SizedBox(height: 10),
    ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: LinearProgressIndicator(
        value: (_speed / 80).clamp(0, 1),
        backgroundColor: AppColors.cardBorder,
        valueColor: AlwaysStoppedAnimation<Color>(
          _speed > 60
              ? AppColors.red
              : _speed > 30
              ? AppColors.orange
              : AppColors.accent,
        ),
        minHeight: 5,
      ),
    ),
  ]);

  Widget _rideBadge() {
    Color c;
    String e;
    switch (_ride) {
      case 'RIDING':
        c = AppColors.green;
        e = '🏍';
        break;
      case 'IMPACT':
        c = AppColors.orange;
        e = '💥';
        break;
      case 'FALLEN':
        c = AppColors.red;
        e = '🆘';
        break;
      case 'SOS':
        c = AppColors.red;
        e = '🚨';
        break;
      default:
        c = AppColors.textDim;
        e = '⏸';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withAlpha(80)),
      ),
      child: Text(
        '$e $_ride',
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _tiltRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      children: [
        Expanded(
          child: _tiltCard('PITCH', 'Trước/Sau', _pitch, AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _tiltCard('ROLL', 'Trái/Phải', _roll, AppColors.accent2),
        ),
      ],
    ),
  );

  Widget _tiltCard(String l, String d, double a, Color c) {
    final danger = a.abs() > 45;
    final cc = danger ? AppColors.red : c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.surface,
        border: Border.all(
          color: danger ? AppColors.red.withAlpha(80) : AppColors.cardBorder,
        ),
      ),
      child: Column(
        children: [
          Text(
            l,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textDim,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 72,
            height: 72,
            child: CustomPaint(
              painter: _TiltGauge(angle: a, color: cc),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${a.toStringAsFixed(1)}°',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w300,
              color: cc,
            ),
          ),
          Text(
            d,
            style: const TextStyle(fontSize: 10, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  Widget _helmet3D() => _card([
    Row(
      children: [
        _iconBox(Icons.view_in_ar, AppColors.accent2),
        const SizedBox(width: 10),
        const Text(
          'GÓC NGHIÊNG MŨ',
          style: TextStyle(
            color: AppColors.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    SizedBox(
      height: 150,
      child: Center(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(_pitch * math.pi / 180)
            ..rotateZ(_roll * math.pi / 180),
          child: Container(
            width: 100,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(35),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.accent.withAlpha(50),
                  AppColors.accent2.withAlpha(80),
                  AppColors.accent2.withAlpha(50),
                ],
              ),
              border: Border.all(
                color: AppColors.accent.withAlpha(100),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withAlpha(40),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.shield,
                size: 48,
                color: AppColors.accent.withAlpha(180),
              ),
            ),
          ),
        ),
      ),
    ),
    const SizedBox(height: 8),
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _imuVal('Pitch', _pitch, AppColors.accent),
        _imuVal('Roll', _roll, AppColors.accent2),
      ],
    ),
  ]);

  Widget _imuVal(String l, double v, Color c) => Column(
    children: [
      Text(
        '${v.toStringAsFixed(1)}°',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c),
      ),
      Text(
        l,
        style: const TextStyle(
          fontSize: 10,
          color: AppColors.textDim,
          letterSpacing: 1,
        ),
      ),
    ],
  );

  Widget _gpsCard() {
    final ok = _lat != 0;
    return _card([
      Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: ok
                  ? AppColors.green.withAlpha(20)
                  : AppColors.textDim.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              ok ? Icons.gps_fixed : Icons.gps_off,
              color: ok ? AppColors.green : AppColors.textDim,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'VỊ TRÍ GPS',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (ok) ...[
        Text(
          '${_lat.toStringAsFixed(6)}, ${_lon.toStringAsFixed(6)}',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontFamily: 'monospace',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Container(
          height: 70,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                AppColors.accent.withAlpha(20),
                AppColors.accent2.withAlpha(20),
              ],
            ),
          ),
          child: Center(
            child: Icon(
              Icons.map,
              size: 36,
              color: AppColors.accent.withAlpha(100),
            ),
          ),
        ),
      ] else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(
                Icons.satellite_alt,
                size: 28,
                color: AppColors.textDim.withAlpha(100),
              ),
              const SizedBox(height: 6),
              const Text(
                'Đang tìm tín hiệu vệ tinh...',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _actions() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      children: [
        Expanded(
          child: _btn(
            Icons.play_circle_fill,
            'Stream',
            AppColors.accent,
            () => _ble.sendCommand('START'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _btn(
            Icons.stop_circle,
            'Dừng',
            AppColors.orange,
            () => _ble.sendCommand('STOP'),
          ),
        ),
      ],
    ),
  );

  Widget _btn(IconData i, String l, Color c, VoidCallback t) => GestureDetector(
    onTap: t,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surface,
        border: Border.all(color: c.withAlpha(60)),
      ),
      child: Column(
        children: [
          Icon(i, color: c, size: 24),
          const SizedBox(height: 4),
          Text(
            l,
            style: TextStyle(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _card(List<Widget> ch) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.surface, AppColors.surfaceLight],
      ),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: ch),
  );

  Widget _iconBox(IconData i, Color c) => Container(
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: c.withAlpha(20),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(i, color: c, size: 18),
  );
}

// ═══════════════════════════════════════════════════════════
class _TiltGauge extends CustomPainter {
  final double angle;
  final Color color;
  _TiltGauge({required this.angle, required this.color});
  @override
  void paint(Canvas c, Size s) {
    final o = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2 - 3;
    c.drawArc(
      Rect.fromCircle(center: o, radius: r),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      Paint()
        ..color = AppColors.cardBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final sw = (angle / 90).clamp(-1.0, 1.0) * math.pi * 0.75;
    c.drawArc(
      Rect.fromCircle(center: o, radius: r),
      math.pi * 1.5,
      sw,
      false,
      Paint()
        ..shader = SweepGradient(
          colors: [color.withAlpha(100), color],
        ).createShader(Rect.fromCircle(center: o, radius: r))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    c.drawCircle(o, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TiltGauge old) =>
      old.angle != angle || old.color != color;
}
