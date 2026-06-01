import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../services/ble_service.dart';
import '../widgets/connection_status.dart';
import '../widgets/gps_map.dart';
import '../widgets/stats_grid.dart';
import '../widgets/control_buttons.dart';

// Pre-define const gradients for performance
const _bgGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF0A0E21),
    Color(0xFF0D1B2A),
    Color(0xFF1B2838),
    Color(0xFF0A0E21),
  ],
);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<BleService, bool>(
      selector: (_, ble) => ble.isConnected,
      builder: (context, isConnected, _) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: _bgGradient),
          child: SafeArea(
            child: isConnected ? const _DashboardView() : const _ConnectView(),
          ),
        ),
      ),
    );
  }
}

// ─── CONNECT SCREEN ────────────────────────────────────────────
class _ConnectView extends StatelessWidget {
  const _ConnectView();

  @override
  Widget build(BuildContext context) {
    return Selector<BleService, BleConnectionState>(
      selector: (_, ble) => ble.state,
      builder: (context, state, _) {
        final scanning =
            state == BleConnectionState.scanning ||
            state == BleConnectionState.connecting;
        final ble = context.read<BleService>();
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 1500),
                  curve: Curves.elasticOut,
                  builder: (_, val, __) => Transform.scale(
                    scale: val,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D2FF).withAlpha(80),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('🪖', style: TextStyle(fontSize: 56)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const ShaderMask(
                  shaderCallback: _titleGradient,
                  child: Text(
                    'SmartHelmet',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'MŨ BẢO HIỂM THÔNG MINH',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withAlpha(100),
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 48),
                GestureDetector(
                  onTap: scanning ? null : () => ble.connect(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(
                          0xFF00D2FF,
                        ).withAlpha(scanning ? 80 : 150),
                        width: 2,
                      ),
                      gradient: LinearGradient(
                        colors: scanning
                            ? [Colors.white12, Colors.white10]
                            : [
                                const Color(0xFF00D2FF).withAlpha(40),
                                const Color(0xFF3A7BD5).withAlpha(30),
                              ],
                      ),
                      boxShadow: scanning
                          ? null
                          : [
                              BoxShadow(
                                color: const Color(0xFF00D2FF).withAlpha(60),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (scanning)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF00D2FF),
                            ),
                          )
                        else
                          const Icon(
                            Icons.bluetooth_rounded,
                            color: Color(0xFF00D2FF),
                            size: 28,
                          ),
                        const SizedBox(width: 14),
                        Text(
                          scanning ? 'Đang quét BLE...' : 'KẾT NỐI MŨ BẢO HIỂM',
                          style: TextStyle(
                            color: scanning ? Colors.white54 : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ConnectionStatusBar(state: state),
                const SizedBox(height: 16),
                Text(
                  'Bật Bluetooth & nguồn mũ bảo hiểm',
                  style: TextStyle(
                    color: Colors.white.withAlpha(80),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Shader _titleGradient(Rect bounds) => const LinearGradient(
    colors: [Color(0xFF00D2FF), Color(0xFF7B2FF7)],
  ).createShader(bounds);
}

// ─── DASHBOARD ──────────────────────────────────────────────────
class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final data = ble.latestData;
    final hasGps = data?.hasGps ?? false;

    return Stack(
      children: [
        RefreshIndicator(
          color: const Color(0xFF00D2FF),
          onRefresh: () async {
            await ble.disconnect();
            await ble.connect();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            addAutomaticKeepAlives: true,
            children: [
              _Header(ble: ble),
              const SizedBox(height: 20),
              _SectionTitle('📍 BẢN ĐỒ GPS', hasGps ? '🟢 LIVE' : '⏳ ĐANG TÌM'),
              const SizedBox(height: 10),
              RepaintBoundary(child: GpsMapWidget(data: data, height: 260)),
              const SizedBox(height: 24),
              const _SectionTitle('📊 CẢM BIẾN', 'REAL-TIME'),
              const SizedBox(height: 10),
              StatsGrid(data: data),
              const SizedBox(height: 24),
              const _SectionTitle('🎮 ĐIỀU KHIỂN', ''),
              const SizedBox(height: 10),
              ControlButtons(
                onAck: () => ble.sendAck(),
                onSos: () => _handleSos(context, ble),
                onTestImpact: () => ble.sendTestImpact(),
              ),
              if (data != null) ...[
                const SizedBox(height: 24),
                const _SectionTitle('📡 DỮ LIỆU THÔ', 'JSON'),
                const SizedBox(height: 10),
                _RawJsonCard(data: data),
              ],
            ],
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: IconButton(
            icon: const Icon(
              Icons.power_settings_new_rounded,
              color: Colors.white24,
              size: 20,
            ),
            onPressed: () => ble.disconnect(),
          ),
        ),
      ],
    );
  }

  static void _handleSos(BuildContext context, BleService ble) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.red.withAlpha(100), width: 1.5),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A0A0A), Color(0xFF0D1B2A)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_rounded, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text(
                'XÁC NHẬN SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gửi tín hiệu cấp cứu khẩn cấp?\nHành động này không thể hoàn tác.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withAlpha(150),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'HỦY',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        ble.sendSos();
                      },
                      child: const Text(
                        'GỬI SOS',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SUB-WIDGETS ────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final BleService ble;
  const _Header({required this.ble});

  @override
  Widget build(BuildContext context) {
    final data = ble.latestData;
    final hasGps = data?.hasGps ?? false;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: hasGps
                  ? [const Color(0xFF00D2FF), const Color(0xFF3A7BD5)]
                  : [Colors.white24, Colors.white12],
            ),
          ),
          child: const Center(
            child: Text('🪖', style: TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SmartHelmet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 7,
                  color: hasGps ? const Color(0xFF00FF88) : Colors.orange,
                ),
                const SizedBox(width: 5),
                Text(
                  hasGps
                      ? 'GPS: ${data!.gps!.satellites} vệ tinh'
                      : 'Đang tìm GPS...',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasGps ? const Color(0xFF00FF88) : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
        const Spacer(),
        ConnectionStatusBar(state: ble.state),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String badge;
  const _SectionTitle(this.title, this.badge);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        if (badge.isNotEmpty) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: const LinearGradient(
                colors: [Color(0xFF00D2FF), Color(0xFF7B2FF7)],
              ),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RawJsonCard extends StatelessWidget {
  final dynamic data;
  const _RawJsonCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final text =
        'Lat: ${data.gps?.lat.toStringAsFixed(5) ?? '--'}  '
        'Lon: ${data.gps?.lon.toStringAsFixed(5) ?? '--'}\n'
        'Speed: ${data.gps?.speedKmh.toStringAsFixed(1) ?? '--'} km/h  '
        'Sats: ${data.gps?.satellites ?? '--'}\n'
        'AI: ${((data.impact?.aiP ?? 0) * 100).toStringAsFixed(1)}%  '
        'Peak G: ${data.impact?.peakG.toStringAsFixed(2) ?? '--'}g\n'
        'Helmet: ${data.helmetId}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(15)),
        gradient: LinearGradient(
          colors: [Colors.white.withAlpha(8), Colors.white.withAlpha(3)],
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withAlpha(120),
          fontSize: 12,
          fontFamily: 'monospace',
          height: 1.6,
        ),
      ),
    );
  }
}
