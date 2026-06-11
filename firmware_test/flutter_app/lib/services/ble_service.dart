import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Dịch vụ BLE kết nối tới ESP32 SmartHelmet
/// Lắng nghe telemetry và alert FALLEN
class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _notifyChar;
  BluetoothCharacteristic? _writeChar;
  StreamSubscription? _notifySub;
  StreamSubscription? _scanSub;
  StreamSubscription? _connectionSub;
  Timer? _timeoutTimer;
  Timer? _retryTimer;
  bool _connecting = false;
  bool _found = false;
  int _retryCount = 0;
  String _buffer = '';

  // Callbacks
  void Function()? onConnected;
  void Function()? onDisconnected;
  void Function(Map<String, dynamic> data)? onTelemetry;
  void Function(Map<String, dynamic> data)? onFallDetected;

  Future<void> init() async {
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first;
    _startScan();
  }

  /// Kết nối tới SmartHelmet - dùng cho ConnectScreen
  /// Ném Exception nếu không tìm thấy sau 30 giây
  Future<void> connectToHelmet() async {
    if (_device != null) return;

    final completer = Completer<void>();

    _startScan(
      onSuccess: () {
        if (!completer.isCompleted) completer.complete();
      },
      onTimeout: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Không tìm thấy mũ SmartHelmet'));
        }
      },
    );

    return completer.future;
  }

  /// Public scan (dùng cho auto-reconnect từ lifecycle)
  void startScanning() => _startScan();

  Future<void> _startScan({
    void Function()? onSuccess,
    void Function()? onTimeout,
  }) async {
    if (_connecting || _device != null) return;
    _connecting = true;
    _found = false;

    // Hủy scan cũ nếu có
    await _cancelScanSub();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 30));

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (_found) return;
      for (final r in results) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.device.advName;
        if (name.contains('SmartHelmet')) {
          _found = true;
          FlutterBluePlus.stopScan();
          _cancelScanSub();
          _timeoutTimer?.cancel();
          _connect(r.device).then((ok) {
            if (ok) onSuccess?.call();
          });
          return;
        }
      }
    });

    // Timeout dùng Timer (có thể cancel)
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 32), () {
      if (_device == null) {
        _connecting = false;
        _cancelScanSub();
        onTimeout?.call();
        _scheduleRetry();
      }
    });
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryCount++;
    final delay = Duration(seconds: math.min(_retryCount * 5, 60));
    _retryTimer = Timer(delay, () => _startScan());
  }

  Future<bool> _connect(BluetoothDevice device) async {
    _device = device;

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );

      // Khám phá services
      final services = await device.discoverServices();

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() ==
            '6e400001-b5a3-f393-e0a9-e50e24dcca9e') {
          for (final c in service.characteristics) {
            final uuid = c.uuid.toString().toLowerCase();

            // Notify (nhận dữ liệu từ ESP32)
            if (uuid == '6e400003-b5a3-f393-e0a9-e50e24dcca9e') {
              _notifyChar = c;
              await c.setNotifyValue(true);

              await _notifySub?.cancel();
              _buffer = '';
              _notifySub = c.onValueReceived.listen((value) {
                _buffer += String.fromCharCodes(value);
                // Buffer fragmented BLE packets, split by newline delimiter
                while (_buffer.contains('\n')) {
                  final idx = _buffer.indexOf('\n');
                  final msg = _buffer.substring(0, idx).trim();
                  _buffer = _buffer.substring(idx + 1);
                  if (msg.isNotEmpty) _parseMessage(msg);
                }
              });
            }

            // Write (gửi lệnh tới ESP32)
            if (uuid == '6e400002-b5a3-f393-e0a9-e50e24dcca9e') {
              _writeChar = c;
            }
          }
        }
      }

      // Lắng nghe disconnect
      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _device = null;
          _notifyChar = null;
          _writeChar = null;
          _notifySub?.cancel();
          _connecting = false;
          onDisconnected?.call();
          _scheduleRetry(); // Tự động scan lại với backoff
        }
      });

      _connecting = false;
      _retryCount = 0;
      onConnected?.call();
      return true;
    } catch (e) {
      _connecting = false;
      _device = null;
      _scheduleRetry(); // Thử lại với backoff delay
      return false;
    }
  }

  Future<void> _cancelScanSub() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  void _parseMessage(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;

      final type = data['type'] ?? '';

      if (type == 'telemetry') {
        onTelemetry?.call(_flattenTelemetry(data));
      } else if (type == 'impact_alert') {
        // ESP32 gửi impact.detected=true, không có state.fall_detected
        final fallDetected = data['impact']?['detected'] == true;
        debugPrint(
            '[BLE] 🔔 Nhan impact_alert: detected=$fallDetected, ai_p=${data['impact']?['ai_p']}, peak_g=${data['impact']?['peak_g']}');

        if (fallDetected) {
          onFallDetected?.call(_flattenImpactAlert(data));
        }
      } else {
        debugPrint('[BLE] Unknown message type: $type');
      }
    } catch (e) {
      debugPrint(
          '[BLE] ❌ Parse error: $e | raw(len=${raw.length}): ${raw.substring(0, raw.length > 100 ? 100 : raw.length)}...');
    }
  }

  /// Làm phẳng JSON telemetry để dễ truy cập
  Map<String, dynamic> _flattenTelemetry(Map<String, dynamic> data) {
    return {
      'ride_state': data['state']?['ride_state'] ?? 'IDLE',
      'fall_detected': data['state']?['fall_detected']?.toString() ?? 'false',
      'pitch_deg': data['imu']?['pitch_deg']?.toString() ?? '0',
      'roll_deg': data['imu']?['roll_deg']?.toString() ?? '0',
      'angular_vel_dps': data['imu']?['angular_vel_dps']?.toString() ?? '0',
      'lat': data['gps']?['lat']?.toString() ?? '0',
      'lon': data['gps']?['lon']?.toString() ?? '0',
      'speed_kmh': data['gps']?['speed_kmh']?.toString() ?? '0',
      'satellites': data['gps']?['satellites']?.toString() ?? '0',
      'gps_source': data['gps']?['source']?.toString() ?? 'none',
      'gps_score': data['gps']?['score']?.toString() ?? '0',
    };
  }

  Map<String, dynamic> _flattenImpactAlert(Map<String, dynamic> data) {
    return {
      'lat': data['gps']?['lat']?.toString() ?? '0',
      'lon': data['gps']?['lon']?.toString() ?? '0',
      'speed_kmh': data['gps']?['speed_kmh']?.toString() ?? '0',
      'peak_g': data['impact']?['peak_g']?.toString() ?? '0',
      'ai_p': data['impact']?['ai_p']?.toString() ?? '0',
      'event_type': data['impact']?['event_type'] ?? 'fall_detected',
    };
  }

  /// Gửi lệnh qua BLE tới ESP32
  Future<void> sendCommand(String cmd) async {
    if (_writeChar != null) {
      await _writeChar!.write(cmd.codeUnits, withoutResponse: false);
    }
  }

  Future<void> dispose() async {
    _timeoutTimer?.cancel();
    _retryTimer?.cancel();
    await _notifySub?.cancel();
    await _scanSub?.cancel();
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _connecting = false;
  }
}
