import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'services/ble_service.dart';
import 'services/beacon_scanner.dart';
import 'services/emergency_service.dart';
import 'screens/fall_alert_screen.dart';

const String EMERGENCY_PHONE = '0868314386';
const String EMERGENCY_PHONE2 = '0365395326';

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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartHelmetApp());
}

class SmartHelmetApp extends StatelessWidget {
  const SmartHelmetApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Helmet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.accent2,
          surface: AppColors.surface,
        ),
        useMaterial3: true,
      ),
      home: const ConnectScreen(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// MÀN HÌNH KẾT NỐI
// ═══════════════════════════════════════════════════════════
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with TickerProviderStateMixin {
  final BleService _ble = BleService();

  bool _bluetoothOn = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  String _statusText = 'Đang kiểm tra Bluetooth...';
  String _statusDetail = '';

  late AnimationController _scanPulse;
  late AnimationController _helmetFloat;
  late AnimationController _dot1, _dot2, _dot3;
  late Animation<double> _pulseAnim;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();

    _scanPulse =
        AnimationController(duration: const Duration(seconds: 2), vsync: this)
          ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _scanPulse, curve: Curves.easeInOut));

    _helmetFloat =
        AnimationController(duration: const Duration(seconds: 3), vsync: this)
          ..repeat(reverse: true);
    _floatAnim = Tween(begin: -8.0, end: 8.0).animate(
        CurvedAnimation(parent: _helmetFloat, curve: Curves.easeInOut));

    _dot1 = AnimationController(
        duration: const Duration(milliseconds: 1200), vsync: this)
      ..repeat();
    _dot2 = AnimationController(
        duration: const Duration(milliseconds: 1200), vsync: this)
      ..repeat();
    _dot3 = AnimationController(
        duration: const Duration(milliseconds: 1200), vsync: this)
      ..repeat();

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
    final state = await FlutterBluePlus.adapterState.first;
    setState(() {
      _bluetoothOn = state == BluetoothAdapterState.on;
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
          _isScanning = false;
          _isConnecting = false;
        }
      });
    });
  }

  Future<void> _connect() async {
    if (!_bluetoothOn) return;

    final scanPerm = await Permission.bluetoothScan.request();
    final connectPerm = await Permission.bluetoothConnect.request();
    if (!scanPerm.isGranted || !connectPerm.isGranted) {
      setState(() {
        _statusText = 'Cần quyền Bluetooth';
        _statusDetail = 'Vào Cài đặt → Quyền → Bluetooth để cấp';
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _isConnecting = false;
      _statusText = 'Đang tìm mũ...';
      _statusDetail = 'Đảm bảo mũ đã được bật nguồn';
    });

    _ble.onConnected = () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _isConnecting = true;
        _statusText = 'Đã tìm thấy!';
        _statusDetail = 'Đang kết nối...';
      });
      // Send phone GPS immediately — don't wait for dashboard.
      _sendInitialGps();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => HelmetDashboard(ble: _ble),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      });
    };

    _ble.onDisconnected = () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _isConnecting = false;
        _statusText = 'Mất kết nối';
        _statusDetail = 'Nhấn nút để kết nối lại';
      });
    };

    try {
      await _ble.connectToHelmet();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _statusText = 'Không tìm thấy mũ';
        _statusDetail = 'Thử lại hoặc kiểm tra mũ đã bật chưa';
      });
    }
  }

  /// Get phone GPS and send to ESP32 right after BLE connects.
  Future<void> _sendInitialGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final acc = pos.accuracy;
      final estSats = acc <= 3
          ? 16
          : acc <= 5
              ? 12
              : acc <= 10
                  ? 8
                  : acc <= 20
                      ? 5
                      : 3;
      final cmd = 'GPS:${pos.latitude.toStringAsFixed(6)},'
          '${pos.longitude.toStringAsFixed(6)},'
          '${(pos.speed * 3.6).toStringAsFixed(1)},$estSats';
      await _ble.sendCommand(cmd);
      debugPrint('[GPS] Sent initial: $cmd (acc: ${acc}m)');
    } catch (e) {
      debugPrint('[GPS] Initial send failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            _buildHelmetIllustration(),
            const Spacer(flex: 1),
            const Text('SMART HELMET',
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 4)),
            const SizedBox(height: 8),
            const Text('Mũ bảo hiểm thông minh',
                style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textDim,
                    letterSpacing: 1.5)),
            const SizedBox(height: 40),
            _buildStatusSection(),
            const SizedBox(height: 32),
            _buildConnectButton(),
            const Spacer(flex: 2),
            Text('phiên bản 2.0.0',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim.withValues(alpha: 0.39))),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHelmetIllustration() {
    return AnimatedBuilder(
      animation: _floatAnim,
      builder: (_, child) => Transform.translate(
          offset: Offset(0, _floatAnim.value), child: child!),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_isScanning || _isConnecting)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 200 * _pulseAnim.value,
                height: 200 * _pulseAnim.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accent
                        .withValues(alpha: _pulseAnim.value * 0.31),
                    width: 2,
                  ),
                ),
              ),
            ),
          if (_isScanning || _isConnecting)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 260 * (1 - _pulseAnim.value * 0.5),
                height: 260 * (1 - _pulseAnim.value * 0.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accent
                        .withValues(alpha: _pulseAnim.value * 0.16),
                    width: 1,
                  ),
                ),
              ),
            ),
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accent.withValues(alpha: 0.12),
                  AppColors.accent2.withValues(alpha: 0.20),
                ],
              ),
              border: Border.all(
                color: (_isScanning || _isConnecting)
                    ? AppColors.accent.withValues(alpha: 0.59)
                    : AppColors.accent.withValues(alpha: 0.24),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_isScanning || _isConnecting
                          ? AppColors.accent
                          : AppColors.accent2)
                      .withValues(alpha: 0.20),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: ClipOval(
              child: CustomPaint(
                painter: _HelmetPainter(
                  mainColor: (_isScanning || _isConnecting)
                      ? AppColors.accent
                      : AppColors.accent,
                  visorColor: const Color(0xFF1A1A2E),
                  accentColor: AppColors.accent2,
                ),
                size: const Size(140, 140),
              ),
            ),
          ),
          Positioned(
            top: 18,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (_isScanning || _isConnecting)
                    ? AppColors.accent
                    : AppColors.textDim,
                boxShadow: (_isScanning || _isConnecting)
                    ? [
                        BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.71),
                            blurRadius: 12,
                            spreadRadius: 3)
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    return Padding(
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
                color: _isConnecting
                    ? AppColors.green
                    : _isScanning
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
          Text(_statusDetail,
              style: const TextStyle(fontSize: 13, color: AppColors.textDim),
              textAlign: TextAlign.center),
          if (_isScanning || _isConnecting) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDot(_dot1, 0),
                const SizedBox(width: 8),
                _buildDot(_dot2, 300),
                const SizedBox(width: 8),
                _buildDot(_dot3, 600),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDot(AnimationController ctrl, int delayMs) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        double t = ((ctrl.value * 1200 + delayMs) % 1200) / 1200;
        double opacity = t < 0.5 ? t * 2 : (1 - t) * 2;
        return Opacity(
          opacity: opacity,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: AppColors.accent),
          ),
        );
      },
    );
  }

  Widget _buildConnectButton() {
    final bool loading = _isScanning || _isConnecting;
    final bool disabled = !_bluetoothOn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50),
      child: GestureDetector(
        onTap: disabled || loading ? null : _connect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: loading
                  ? [
                      AppColors.accent.withValues(alpha: 0.39),
                      AppColors.accent2.withValues(alpha: 0.39)
                    ]
                  : disabled
                      ? [
                          AppColors.textDim.withValues(alpha: 0.31),
                          AppColors.textDim.withValues(alpha: 0.16)
                        ]
                      : [AppColors.accent, AppColors.accent2],
            ),
            boxShadow: loading
                ? [
                    BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.24),
                        blurRadius: 20,
                        spreadRadius: 2)
                  ]
                : disabled
                    ? []
                    : [
                        BoxShadow(
                            color: AppColors.accent2.withValues(alpha: 0.31),
                            blurRadius: 15,
                            spreadRadius: 1)
                      ],
          ),
          child: Center(
            child: loading
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.accent),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      _isConnecting ? 'ĐANG KẾT NỐI...' : 'ĐANG TÌM...',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2),
                    ),
                  ])
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(
                        disabled
                            ? Icons.bluetooth_disabled
                            : Icons.bluetooth_connected,
                        color: Colors.white,
                        size: 24),
                    const SizedBox(width: 12),
                    Text(
                      disabled ? 'BẬT BLUETOOTH' : 'KẾT NỐI VỚI MŨ',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// DASHBOARD CHÍNH
// ═══════════════════════════════════════════════════════════
class HelmetDashboard extends StatefulWidget {
  final BleService ble;
  const HelmetDashboard({super.key, required this.ble});
  @override
  State<HelmetDashboard> createState() => _HelmetDashboardState();
}

class _HelmetDashboardState extends State<HelmetDashboard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  BleService get _ble => widget.ble;

  // Dữ liệu từ ESP32
  bool _connected = true;
  String _ride = 'IDLE';
  double _pitch = 0, _roll = 0;
  double _espLat = 0, _espLon = 0, _speed = 0;
  int _sats = 0;
  String _gpsSource = 'none'; // NEO-6M | Phone | Cache | None
  int _gpsScore = 0; // điểm chất lượng GPS selector

  // GPS từ điện thoại
  double _phoneLat = 0, _phoneLon = 0;
  bool _usingPhoneGps = false;
  String _gpsStatus = 'Đang khởi động GPS...';
  bool _gpsPermGranted = false;

  // Getters — ưu tiên phone GPS nếu có
  double get _lat => _usingPhoneGps ? _phoneLat : _espLat;
  double get _lon => _usingPhoneGps ? _phoneLon : _espLon;

  Timer? _phoneGpsTimer;
  StreamSubscription<Position>? _phoneGpsSub;
  Position? _lastPhonePosition;
  final BeaconScanner _beaconScanner = BeaconScanner();

  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulse =
        AnimationController(duration: const Duration(seconds: 2), vsync: this)
          ..repeat(reverse: true);

    _ble.onTelemetry = (d) {
      if (!mounted) return;
      setState(() {
        _ride = d['ride_state'] ?? 'IDLE';
        _pitch = double.tryParse(d['pitch_deg']?.toString() ?? '0') ?? 0;
        _roll = double.tryParse(d['roll_deg']?.toString() ?? '0') ?? 0;
        _espLat = double.tryParse(d['lat']?.toString() ?? '0') ?? 0;
        _espLon = double.tryParse(d['lon']?.toString() ?? '0') ?? 0;
        _speed = double.tryParse(d['speed_kmh']?.toString() ?? '0') ?? 0;
        _sats = int.tryParse(d['satellites']?.toString() ?? '0') ?? 0;
        _gpsSource = d['gps_source'] ?? 'none';
        _gpsScore = int.tryParse(d['gps_score']?.toString() ?? '0') ?? 0;
      });
    };

    _ble.onFallDetected = (d) => _showFall(d);

    _ble.onDisconnected = () {
      if (!mounted) return;
      setState(() => _connected = false);
      _stopPhoneGps();
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, __, ___) => const ConnectScreen(),
          transitionsBuilder: (_, a, __, c) =>
              FadeTransition(opacity: a, child: c),
        ));
      });
    };

    // ✅ Xin quyền GPS ngay khi dashboard mở
    _initGps();

    // 🔵 BLE Emergency Beacon Scanner - phát hiện SOS từ mũ khác
    _beaconScanner.onEmergencyDetected = (beacon) {
      debugPrint('[BEACON] 🆘 SOS tu mu khac! ${beacon.lat},${beacon.lon}');
      if (!mounted) return;
      // Hiển thị alert: có người gặp nạn gần đây
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          icon: const Icon(Icons.warning_amber, color: Colors.red, size: 48),
          title: const Text('🚨 Phát hiện tín hiệu cấp cứu!',
              style: TextStyle(color: Colors.white)),
          content: Text(
            'Có người đội mũ bảo hiểm gần bạn bị ${beacon.isFall ? "NGÃ" : "VA CHẠM"}!\n\n'
            '📍 GPS: ${beacon.lat.toStringAsFixed(5)}, ${beacon.lon.toStringAsFixed(5)}\n'
            '💥 Lực: ${beacon.peakG.toStringAsFixed(1)}g\n'
            '🧠 AI: ${(beacon.aiProbability * 100).toStringAsFixed(0)}%\n\n'
            'Vui lòng kiểm tra và gọi cấp cứu nếu cần!',
            style: const TextStyle(color: Color(0xFFB0B0B0)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ĐÓNG', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                EmergencyService.call('115');
              },
              icon: const Icon(Icons.call, color: Colors.white),
              label: const Text('GỌI 115'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    };
    _beaconScanner.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPhoneGps();
    _beaconScanner.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _ble.startScanning();
      // Khởi động lại GPS nếu bị dừng khi app vào background
      if (_gpsPermGranted && _phoneGpsSub == null) {
        _startPhoneGpsStream();
      }
    }
    if (s == AppLifecycleState.paused) {
      // Không dừng GPS — vẫn cần gửi vị trí khi màn hình tắt
    }
  }

  // ═══ KHỞI TẠO GPS ═══
  Future<void> _initGps() async {
    // Bước 1: Kiểm tra Location Service có bật không
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() => _gpsStatus = '📵 Vị trí chưa bật — Vào Cài đặt → Vị trí');
      debugPrint('[GPS] Location service chưa bật');
      return;
    }

    // Bước 2: Xin quyền qua permission_handler (hiển thị dialog rõ hơn)
    final locPerm = await Permission.locationWhenInUse.request();
    if (locPerm.isDenied) {
      if (!mounted) return;
      setState(() => _gpsStatus = '❌ Quyền vị trí bị từ chối');
      debugPrint('[GPS] Quyền bị từ chối');
      return;
    }
    if (locPerm.isPermanentlyDenied) {
      if (!mounted) return;
      setState(() => _gpsStatus = '⚙️ Vào Cài đặt → Quyền → Vị trí → Cho phép');
      await openAppSettings();
      return;
    }

    // Bước 3: Double-check qua Geolocator
    LocationPermission geoPermission = await Geolocator.checkPermission();
    if (geoPermission == LocationPermission.denied) {
      geoPermission = await Geolocator.requestPermission();
    }
    if (geoPermission == LocationPermission.deniedForever ||
        geoPermission == LocationPermission.denied) {
      if (!mounted) return;
      setState(() => _gpsStatus = '❌ Không có quyền GPS');
      return;
    }

    _gpsPermGranted = true;
    if (!mounted) return;
    setState(() => _gpsStatus = '🛰 Đang lấy vị trí...');
    debugPrint('[GPS] Quyền OK — bắt đầu lấy vị trí');

    // Bước 4: Lấy vị trí ngay lập tức (không đợi di chuyển)
    await _getInitialPosition();

    // Bước 5: Bắt đầu stream liên tục
    _startPhoneGpsStream();

    // Bước 6: Gửi GPS cho ESP32 mỗi 2 giây
    _phoneGpsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _sendPhoneGpsToEsp32();
    });
  }

  // ✅ Fix: Lấy vị trí ngay lập tức khi mở app — không cần di chuyển
  Future<void> _getInitialPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lastPhonePosition = pos;
      if (!mounted) return;
      setState(() {
        _phoneLat = pos.latitude;
        _phoneLon = pos.longitude;
        _usingPhoneGps = true;
        _gpsStatus = '✅ GPS đang hoạt động';
      });
      debugPrint(
          '[GPS] Vị trí ban đầu: ${pos.latitude}, ${pos.longitude} (acc: ${pos.accuracy}m)');
    } catch (e) {
      debugPrint('[GPS] Không lấy được vị trí ban đầu: $e');
      if (mounted) setState(() => _gpsStatus = '⚠️ Đang tìm tín hiệu GPS...');
    }
  }

  // ✅ Fix: distanceFilter = 0 — cập nhật liên tục kể cả đứng yên
  void _startPhoneGpsStream() {
    _phoneGpsSub?.cancel();
    _phoneGpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // ✅ 0 = cập nhật liên tục, không cần di chuyển
      ),
    ).listen(
      (pos) {
        _lastPhonePosition = pos;
        debugPrint(
            '[GPS] Stream: ${pos.latitude}, ${pos.longitude} | acc: ${pos.accuracy}m | speed: ${(pos.speed * 3.6).toStringAsFixed(1)} km/h');
        if (!mounted) return;
        setState(() {
          _phoneLat = pos.latitude;
          _phoneLon = pos.longitude;
          _usingPhoneGps = true;
          _gpsStatus = '✅ GPS đang hoạt động';
          // Fallback: chỉ dùng tốc độ phone khi ESP32 không có nguồn GPS nào
          if (_gpsSource == 'none' || _gpsSource == 'Cache') {
            _speed = pos.speed * 3.6; // m/s → km/h
          }
        });
      },
      onError: (e) {
        debugPrint('[GPS] Stream error: $e');
        if (mounted) setState(() => _gpsStatus = '⚠️ Lỗi GPS: $e');
      },
    );
  }

  void _stopPhoneGps() {
    _phoneGpsTimer?.cancel();
    _phoneGpsTimer = null;
    _phoneGpsSub?.cancel();
    _phoneGpsSub = null;
    _lastPhonePosition = null;
  }

  Future<void> _sendPhoneGpsToEsp32() async {
    if (!_connected) return;
    try {
      final pos = _lastPhonePosition;
      if (pos == null) return;
      final speedKmh = pos.speed * 3.6;
      // Ước lượng số vệ tinh từ độ chính xác: accuracy càng thấp → càng nhiều vệ tinh
      final acc = pos.accuracy;
      final estSats = acc <= 3
          ? 16
          : acc <= 5
              ? 12
              : acc <= 10
                  ? 8
                  : acc <= 20
                      ? 5
                      : 3;
      final cmd =
          'GPS:${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)},${speedKmh.toStringAsFixed(1)},$estSats';
      debugPrint('[GPS] → ESP32: $cmd (acc: ${acc}m, estSats: $estSats)');
      await _ble.sendCommand(cmd);
    } catch (e) {
      debugPrint('[GPS] Send error: $e');
    }
  }

  void _showFall(Map<String, dynamic> d) {
    final fallLat = double.tryParse(d['lat']?.toString() ?? '0') ?? _lat;
    final fallLon = double.tryParse(d['lon']?.toString() ?? '0') ?? _lon;
    final fallPeakG = double.tryParse(d['peak_g']?.toString() ?? '0') ?? 0;
    final fallAiP = double.tryParse(d['ai_p']?.toString() ?? '0') ?? 0;

    debugPrint(
        '[FALL] Show alert: lat=$fallLat lon=$fallLon peakG=$fallPeakG aiP=$fallAiP');

    Navigator.of(context).push(PageRouteBuilder(
      fullscreenDialog: true,
      pageBuilder: (_, __, ___) => FallAlertScreen(
        latitude: fallLat,
        longitude: fallLon,
        peakG: fallPeakG,
        aiProbability: fallAiP,
        emergencyPhone: EMERGENCY_PHONE,
        emergencyPhone2: EMERGENCY_PHONE2,
        onAck: () {
          _ble.sendCommand('ACK');
          Navigator.of(context).pop();
        },
        onSos: () => _ble.sendCommand('SOS'),
      ),
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
    ));
  }

  // ═══ BUILD ═══
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(children: [
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
          ]),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
            AppColors.surfaceLight,
            AppColors.surface,
            AppColors.bg
          ])),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🪖 Smart Helmet',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Row(children: [
            AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _connected ? AppColors.green : AppColors.red,
                        boxShadow: [
                          BoxShadow(
                              color:
                                  (_connected ? AppColors.green : AppColors.red)
                                      .withValues(alpha: _pulse.value * 0.59),
                              blurRadius: 10,
                              spreadRadius: 2)
                        ]))),
            const SizedBox(width: 8),
            Text(_connected ? 'Đã kết nối' : 'Mất kết nối',
                style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
          ]),
        ]),
        GestureDetector(
          onTap: () {
            _ble.sendCommand('SOS');
            _showFall({});
          },
          child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      colors: [AppColors.red, Color(0xFFD50000)]),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.31),
                        blurRadius: 20,
                        spreadRadius: 2)
                  ]),
              child: const Icon(Icons.sos, color: Colors.white, size: 24)),
        ),
      ]),
    );
  }

  Widget _speedCard() {
    return _card([
      Row(children: [
        _iconBox(Icons.speed, AppColors.accent),
        const SizedBox(width: 10),
        const Text('TỐC ĐỘ',
            style: TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2)),
        const Spacer(),
        _gpsSourceBadge(),
        const SizedBox(width: 6),
        _rideBadge(),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(_speed.toStringAsFixed(1),
                key: ValueKey(_speed.toStringAsFixed(1)),
                style: const TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.w200,
                    color: Colors.white,
                    height: 1,
                    letterSpacing: -3))),
        const Padding(
            padding: EdgeInsets.only(bottom: 8, left: 2),
            child: Text('km/h',
                style: TextStyle(fontSize: 15, color: AppColors.textDim))),
        const Spacer(),
        Column(children: [
          Icon(Icons.satellite_alt,
              color: _sats > 0 ? AppColors.accent : AppColors.textDim,
              size: 22),
          const SizedBox(height: 2),
          Text('$_sats',
              style: TextStyle(
                  color: _sats > 0 ? AppColors.accent : AppColors.textDim,
                  fontWeight: FontWeight.bold)),
        ]),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
              value: (_speed / 80).clamp(0, 1),
              backgroundColor: AppColors.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(_speed > 60
                  ? AppColors.red
                  : _speed > 30
                      ? AppColors.orange
                      : AppColors.accent),
              minHeight: 5)),
    ]);
  }

  /// Badge hiển thị nguồn GPS đang active (NEO-6M ↔ Phone luân phiên)
  Widget _gpsSourceBadge() {
    final isNeo = _gpsSource == 'NEO-6M';
    final isPhone = _gpsSource == 'Phone';
    final color = isNeo
        ? AppColors.orange
        : isPhone
            ? AppColors.accent
            : AppColors.textDim;
    final icon = isNeo
        ? Icons.memory
        : isPhone
            ? Icons.phone_android
            : Icons.gps_off;
    final label = _gpsSource == 'NEO-6M'
        ? 'MŨ'
        : _gpsSource == 'Phone'
            ? 'PHONE'
            : _gpsSource == 'Cache'
                ? 'CACHE'
                : 'NO GPS';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5)),
      ]),
    );
  }

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
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withValues(alpha: 0.31))),
        child: Text('$e $_ride',
            style: TextStyle(
                color: c,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)));
  }

  Widget _tiltRow() {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Expanded(
              child: _tiltCard('PITCH', 'Trước/Sau', _pitch, AppColors.accent)),
          const SizedBox(width: 12),
          Expanded(
              child: _tiltCard('ROLL', 'Trái/Phải', _roll, AppColors.accent2)),
        ]));
  }

  Widget _tiltCard(String label, String desc, double angle, Color color) {
    final danger = angle.abs() > 45;
    final c = danger ? AppColors.red : color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppColors.surface,
          border: Border.all(
              color: danger
                  ? AppColors.red.withValues(alpha: 0.31)
                  : AppColors.cardBorder)),
      child: Column(children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.textDim,
                fontWeight: FontWeight.w700,
                letterSpacing: 2)),
        const SizedBox(height: 10),
        SizedBox(
            width: 72,
            height: 72,
            child: CustomPaint(painter: _TiltGauge(angle: angle, color: c))),
        const SizedBox(height: 6),
        Text('${angle.toStringAsFixed(1)}°',
            style:
                TextStyle(fontSize: 22, fontWeight: FontWeight.w300, color: c)),
        Text(desc,
            style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
      ]),
    );
  }

  Widget _helmet3D() {
    return _card([
      Row(children: [
        _iconBox(Icons.view_in_ar, AppColors.accent2),
        const SizedBox(width: 10),
        const Text('GÓC NGHIÊNG MŨ',
            style: TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2)),
      ]),
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
                    height: 130,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(35),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.16),
                              blurRadius: 30,
                              spreadRadius: 5)
                        ]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(35),
                      child: CustomPaint(
                        painter: _HelmetPainter(
                          mainColor: AppColors.accent,
                          visorColor: const Color(0xFF1A1A2E),
                          accentColor: AppColors.accent2,
                        ),
                        size: const Size(100, 130),
                      ),
                    ),
                  )))),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _imuVal('Pitch', _pitch, AppColors.accent),
        _imuVal('Roll', _roll, AppColors.accent2),
      ]),
    ]);
  }

  Widget _imuVal(String l, double v, Color c) => Column(children: [
        Text('${v.toStringAsFixed(1)}°',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c)),
        Text(l,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textDim, letterSpacing: 1)),
      ]);

  // ✅ GPS Card — hiển thị bản đồ + vị trí
  Widget _gpsCard() {
    final ok = _lat != 0 && _lon != 0;
    return _card([
      Row(children: [
        AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: ok
                    ? AppColors.green.withValues(alpha: 0.08)
                    : AppColors.textDim.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(ok ? Icons.gps_fixed : Icons.gps_not_fixed,
                color: ok ? AppColors.green : AppColors.orange, size: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'VỊ TRÍ',
                style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5),
              ),
            ],
          ),
        ),
      ]),
      const SizedBox(height: 14),
      if (ok) ...[
        // ═══ BẢN ĐỒ THẬT ═══
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 220,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(_lat, _lon),
                initialZoom: 16.0,
                minZoom: 5.0,
                maxZoom: 18.0,
              ),
              children: [
                // Lớp nền OpenStreetMap (theme sáng, miễn phí)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.smarthelmet.app',
                ),
                // Marker vị trí hiện tại
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_lat, _lon),
                      width: 36,
                      height: 36,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.accent,
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.accent,
                                    blurRadius: 12,
                                    spreadRadius: 3)
                              ],
                            ),
                            child: const Icon(Icons.my_location,
                                color: Colors.white, size: 12),
                          ),
                          // Mũi tên chỉ xuống
                          CustomPaint(
                            size: const Size(10, 10),
                            painter: _MarkerArrowPainter(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Vòng tròn accuracy
                if (_lastPhonePosition != null &&
                    _lastPhonePosition!.accuracy > 0)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(_lat, _lon),
                        radius: _lastPhonePosition!.accuracy,
                        color: AppColors.accent.withValues(alpha: 0.08),
                        borderStrokeWidth: 1.5,
                        borderColor: AppColors.accent.withValues(alpha: 0.24),
                      ),
                    ],
                  ),
                // Attribution
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      '© OpenStreetMap contributors',
                      textStyle: TextStyle(
                          fontSize: 9,
                          color: AppColors.textDim.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Tọa độ text nhỏ bên dưới bản đồ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: AppColors.surfaceLight,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                '${_lat.toStringAsFixed(6)}, ${_lon.toStringAsFixed(6)}',
                style: const TextStyle(
                    fontSize: 13, color: Colors.white, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        // Accuracy indicator
        if (_lastPhonePosition != null) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.radar,
                size: 12, color: AppColors.textDim.withValues(alpha: 0.6)),
            const SizedBox(width: 4),
            Text(
              'Độ chính xác: ±${_lastPhonePosition!.accuracy.toStringAsFixed(0)}m',
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textDim.withValues(alpha: 0.6)),
            ),
          ]),
        ],
      ] else
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _gpsStatus,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (_gpsStatus.contains('Cài đặt') ||
                  _gpsStatus.contains('từ chối'))
                TextButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings,
                      size: 14, color: AppColors.accent),
                  label: const Text('Mở Cài đặt',
                      style: TextStyle(color: AppColors.accent, fontSize: 12)),
                ),
            ])),
    ]);
  }

  Widget _actions() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(
            child: _btn(Icons.play_circle_fill, 'Stream', AppColors.accent,
                () => _ble.sendCommand('START'))),
        const SizedBox(width: 12),
        Expanded(
            child: _btn(Icons.stop_circle, 'Dừng', AppColors.orange,
                () => _ble.sendCommand('STOP'))),
      ]));

  Widget _btn(IconData i, String l, Color c, VoidCallback t) => GestureDetector(
      onTap: t,
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.surface,
              border: Border.all(color: c.withValues(alpha: 0.24))),
          child: Column(children: [
            Icon(i, color: c, size: 24),
            const SizedBox(height: 4),
            Text(l,
                style: TextStyle(
                    color: c, fontSize: 11, fontWeight: FontWeight.w600)),
          ])));

  Widget _card(List<Widget> children) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.surface, AppColors.surfaceLight]),
          border: Border.all(color: AppColors.cardBorder)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children));

  Widget _iconBox(IconData i, Color c) => Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10)),
      child: Icon(i, color: c, size: 18));
}

// ═══ HELMET PAINTER: vẽ mũ bảo hiểm chân thực ═══
class _HelmetPainter extends CustomPainter {
  final Color mainColor;
  final Color visorColor;
  final Color accentColor;

  _HelmetPainter({
    required this.mainColor,
    required this.visorColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // ── Body helmet (dome) ──
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-0.3, -0.8),
        end: const Alignment(0.3, 0.6),
        colors: [
          mainColor.withValues(alpha: 0.25),
          mainColor.withValues(alpha: 0.45),
          mainColor.withValues(alpha: 0.20),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final helmetPath = Path();
    // Dome top
    helmetPath.moveTo(cx - w * 0.32, cy - h * 0.18);
    helmetPath.cubicTo(
      cx - w * 0.42, cy - h * 0.38, // control 1
      cx - w * 0.38, cy - h * 0.50, // control 2
      cx, cy - h * 0.50, // top center
    );
    helmetPath.cubicTo(
      cx + w * 0.38,
      cy - h * 0.50,
      cx + w * 0.42,
      cy - h * 0.38,
      cx + w * 0.32,
      cy - h * 0.18,
    );
    // Right side down
    helmetPath.cubicTo(
      cx + w * 0.44,
      cy + h * 0.05,
      cx + w * 0.36,
      cy + h * 0.30,
      cx + w * 0.28,
      cy + h * 0.38,
    );
    // Bottom curved
    helmetPath.quadraticBezierTo(
      cx + w * 0.12,
      cy + h * 0.46,
      cx,
      cy + h * 0.44,
    );
    // Left side up
    helmetPath.quadraticBezierTo(
      cx - w * 0.12,
      cy + h * 0.46,
      cx - w * 0.28,
      cy + h * 0.38,
    );
    helmetPath.cubicTo(
      cx - w * 0.36,
      cy + h * 0.30,
      cx - w * 0.44,
      cy + h * 0.05,
      cx - w * 0.32,
      cy - h * 0.18,
    );
    helmetPath.close();

    canvas.drawPath(helmetPath, bodyPaint);

    // ── Outline ──
    canvas.drawPath(
      helmetPath,
      Paint()
        ..color = mainColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // ── Visor (kính chắn) ──
    final visorPath = Path();
    visorPath.moveTo(cx - w * 0.24, cy - h * 0.18);
    visorPath.cubicTo(
      cx - w * 0.20,
      cy - h * 0.30,
      cx,
      cy - h * 0.28,
      cx + w * 0.24,
      cy - h * 0.18,
    );
    visorPath.cubicTo(
      cx + w * 0.28,
      cy - h * 0.06,
      cx + w * 0.32,
      cy + h * 0.08,
      cx + w * 0.26,
      cy + h * 0.18,
    );
    visorPath.cubicTo(
      cx + w * 0.18,
      cy + h * 0.10,
      cx + w * 0.08,
      cy + h * 0.05,
      cx,
      cy + h * 0.04,
    );
    visorPath.cubicTo(
      cx - w * 0.08,
      cy + h * 0.05,
      cx - w * 0.18,
      cy + h * 0.10,
      cx - w * 0.26,
      cy + h * 0.18,
    );
    visorPath.cubicTo(
      cx - w * 0.32,
      cy + h * 0.08,
      cx - w * 0.28,
      cy - h * 0.06,
      cx - w * 0.24,
      cy - h * 0.18,
    );
    visorPath.close();

    canvas.drawPath(
      visorPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            visorColor.withValues(alpha: 0.75),
            visorColor.withValues(alpha: 0.55),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.fill,
    );

    // ── Visor highlight ──
    final highlightPath = Path();
    highlightPath.moveTo(cx - w * 0.12, cy - h * 0.22);
    highlightPath.quadraticBezierTo(
      cx,
      cy - h * 0.30,
      cx + w * 0.08,
      cy - h * 0.20,
    );
    canvas.drawPath(
      highlightPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // ── Top vent ──
    final ventPaint = Paint()
      ..color = mainColor.withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Vent lines on top
    for (int i = -1; i <= 1; i++) {
      final vx = cx + i * w * 0.08;
      canvas.drawLine(
        Offset(vx - 4, cy - h * 0.38),
        Offset(vx + 4, cy - h * 0.32),
        ventPaint,
      );
    }

    // ── Chin vent ──
    final chinVent = Path();
    chinVent.moveTo(cx - w * 0.10, cy + h * 0.32);
    chinVent.lineTo(cx - w * 0.04, cy + h * 0.36);
    chinVent.lineTo(cx + w * 0.04, cy + h * 0.36);
    chinVent.lineTo(cx + w * 0.10, cy + h * 0.32);
    canvas.drawPath(
      chinVent,
      Paint()
        ..color = mainColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // ── Side accents ──
    for (final side in [-1.0, 1.0]) {
      canvas.drawLine(
        Offset(cx + side * w * 0.20, cy - h * 0.12),
        Offset(cx + side * w * 0.32, cy + h * 0.08),
        Paint()
          ..color = accentColor.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HelmetPainter oldDelegate) =>
      mainColor != oldDelegate.mainColor ||
      visorColor != oldDelegate.visorColor ||
      accentColor != oldDelegate.accentColor;
}

// ═══ MARKER ARROW PAINTER: mũi tên nhọn dưới marker GPS ═══
class _MarkerArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;
    path.moveTo(w * 0.5, h); // đỉnh dưới
    path.lineTo(w * 0.15, h * 0.2); // trái trên
    path.lineTo(w * 0.5, h * 0.55); // lõm giữa
    path.lineTo(w * 0.85, h * 0.2); // phải trên
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══ CUSTOM PAINTER ═══
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
          ..strokeCap = StrokeCap.round);
    final sw = (angle / 90).clamp(-1.0, 1.0) * math.pi * 0.75;
    c.drawArc(
        Rect.fromCircle(center: o, radius: r),
        math.pi * 1.5,
        sw,
        false,
        Paint()
          ..shader =
              SweepGradient(colors: [color.withValues(alpha: 0.39), color])
                  .createShader(Rect.fromCircle(center: o, radius: r))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    c.drawCircle(
        o,
        3,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _TiltGauge o) =>
      o.angle != angle || o.color != color;
}
