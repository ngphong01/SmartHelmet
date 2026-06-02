import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/telemetry_data.dart';
import '../utils/app_logger.dart';
import 'gps_fallback_service.dart';

/// Service UUID & Characteristic UUIDs cho Nordic UART Service
const String _serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _charTxUuid =
    '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // NOTIFY (mũ → app)
const String _charRxUuid =
    '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // WRITE  (app → mũ)

enum BleConnectionState { disconnected, scanning, connecting, connected }

class BleService extends ChangeNotifier {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  BleConnectionState _state = BleConnectionState.disconnected;
  TelemetryData? _latestData;
  StreamSubscription? _txSubscription;
  String _buffer = ''; // Buffer dữ liệu BLE

  // ============================================================
  // AUTO-RECONNECT + HEARTBEAT
  // ============================================================
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime _lastHeartbeat = DateTime.now();
  bool _autoReconnect = true;
  static const _reconnectInterval = Duration(seconds: 5);
  static const _heartbeatInterval = Duration(seconds: 5);
  static const _heartbeatTimeout = Duration(seconds: 15);

  // ============================================================
  // GPS FALLBACK
  // ============================================================
  final GpsFallbackService gpsFallback = GpsFallbackService();

  // Getters
  BleConnectionState get state => _state;
  TelemetryData? get latestData => _latestData;
  bool get isConnected => _state == BleConnectionState.connected;
  bool get isHeartbeatAlive =>
      DateTime.now().difference(_lastHeartbeat) < _heartbeatTimeout;
  bool get autoReconnect => _autoReconnect;
  set autoReconnect(bool v) => _autoReconnect = v;

  /// Bật chế độ tự động reconnect
  void startAutoReconnect() {
    _autoReconnect = true;
    _startReconnectTimer();
    _startHeartbeatMonitor();
  }

  /// Tắt chế độ tự động reconnect
  void stopAutoReconnect() {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(_reconnectInterval, (_) async {
      if (!_autoReconnect) return;
      if (_state == BleConnectionState.disconnected) {
        logRetry('BLE', 'Auto-reconnect...');
        incrementReconnect();
        await connect();
      }
    });
  }

  void _startHeartbeatMonitor() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_state == BleConnectionState.connected && !isHeartbeatAlive) {
        logWarn('BLE', 'Heartbeat timeout! Coi nhu mat ket noi');
        incrementDisconnect();
        _state = BleConnectionState.disconnected;
        notifyListeners();
        // Sẽ được reconnect timer xử lý
      }
    });
  }

  /// Xử lý heartbeat từ dữ liệu telemetry
  void _updateHeartbeat() {
    _lastHeartbeat = DateTime.now();
  }

  /// Quét và kết nối tới thiết bị có tên "SmartHelmet"
  Future<bool> connect() async {
    if (_state == BleConnectionState.connected) return true;

    _state = BleConnectionState.scanning;
    notifyListeners();

    try {
      // Dừng scan cũ nếu có
      await FlutterBluePlus.stopScan();

      BluetoothDevice? found;

      // ─── Cách 1: Kiểm tra thiết bị đã paired ──────────────────
      logInfo('BLE', '🔍 Kiem tra paired devices...');
      final paired = await FlutterBluePlus.systemDevices([]);
      logInfo('BLE', 'Co ${paired.length} thiet bi paired');
      for (final d in paired) {
        logDebug('BLE', '  → ${d.platformName} | ${d.remoteId}');
        try {
          await d.connect(
            autoConnect: false,
            timeout: const Duration(seconds: 5),
          );
          await d.discoverServices();
          for (final srv in d.servicesList) {
            if (srv.uuid.toString().toLowerCase() == _serviceUuid) {
              found = d;
              logOk('BLE', 'Tim thay SmartHelmet trong paired!');
              break;
            }
          }
        } catch (e) {
          debugPrint('[BLE] Lỗi paired device: $e');
        }
        if (found != null) break;
        try {
          await d.disconnect();
        } catch (_) {}
      }

      // ─── Cách 2: Scan BLE (không filter UUID vì Android hay lỗi) ─
      if (found == null) {
        logInfo('BLE', '🔍 Bat dau scan BLE...');
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

        await for (final results in FlutterBluePlus.scanResults) {
          logDebug('BLE', '📡 Tim thay ${results.length} thiet bi BLE');
          for (final r in results) {
            final name = (r.device.platformName).toUpperCase();
            final advName = (r.advertisementData.advName ?? '').toUpperCase();
            final mac = r.device.remoteId.toString().toUpperCase();
            logDebug(
              'BLE',
              '  → Ten: "$name" | Adv: "$advName" | RSSI: ${r.rssi}',
            );

            if (name.contains('SMARTHELMET') ||
                advName.contains('SMARTHELMET') ||
                mac == '80:F3:DA:A9:A8:9A') {
              found = r.device;
              logOk('BLE', 'Tim thay SmartHelmet! $name RSSI=${r.rssi}');
              break;
            }
          }
          if (found != null) break;
        }

        await FlutterBluePlus.stopScan();
      }

      if (found == null) {
        logFail('BLE', 'Khong tim thay SmartHelmet');
        _state = BleConnectionState.disconnected;
        notifyListeners();
        return false;
      }

      logBleState('scanning', 'connecting');
      _state = BleConnectionState.connecting;
      notifyListeners();

      _device = found;
      try {
        if (_device!.isDisconnected) {
          await _device!.connect(autoConnect: false);
        }
        await _device!.discoverServices();

        try {
          final mtu = await _device!.requestMtu(512);
          logInfo('BLE', '📡 MTU negotiated: $mtu bytes');
        } catch (e) {
          debugPrint('[BLE] ⚠️ Không thể request MTU 512: $e');
          // Fallback: firmware sẽ tự chunk 180 byte
        }
      } catch (e) {
        logFail('BLE', 'Loi connect: $e');
        try {
          await _device!.disconnect();
        } catch (_) {}
        _state = BleConnectionState.disconnected;
        notifyListeners();
        return false;
      }

      // Tìm Nordic UART Service
      BluetoothService? uartService;
      for (final srv in _device!.servicesList) {
        if (srv.uuid.toString().toLowerCase() == _serviceUuid) {
          uartService = srv;
          break;
        }
      }

      if (uartService == null) {
        logFail('BLE', 'Khong tim thay UART Service');
        await _device!.disconnect();
        _state = BleConnectionState.disconnected;
        notifyListeners();
        return false;
      }

      // Lấy TX characteristic (NOTIFY - mũ gửi dữ liệu)
      for (final c in uartService.characteristics) {
        if (c.uuid.toString().toLowerCase() == _charTxUuid) {
          _txChar = c;
        } else if (c.uuid.toString().toLowerCase() == _charRxUuid) {
          _rxChar = c;
        }
      }

      if (_txChar == null || _rxChar == null) {
        logFail('BLE', 'Khong tim thay TX/RX characteristic');
        await _device!.disconnect();
        _state = BleConnectionState.disconnected;
        notifyListeners();
        return false;
      }

      // Lắng nghe dữ liệu từ TX characteristic
      await _txChar!.setNotifyValue(true);
      _txSubscription = _txChar!.onValueReceived.listen(_onDataReceived);

      // Gửi lệnh START để bắt đầu stream
      await sendCommand('START');

      _state = BleConnectionState.connected;
      notifyListeners();

      // Bắt đầu auto-reconnect và heartbeat monitor
      startAutoReconnect();

      logOk('BLE', 'Da ket noi va bat dau stream du lieu!');
      return true;
    } catch (e) {
      logFail('BLE', 'Connect error: $e');
      _state = BleConnectionState.disconnected;
      notifyListeners();
      return false;
    }
  }

  /// Gửi lệnh qua RX characteristic
  Future<void> sendCommand(String cmd) async {
    if (_rxChar == null) return;
    try {
      await _rxChar!.write(utf8.encode(cmd), withoutResponse: false);
      logTx('BLE', 'Gui: $cmd');
    } catch (e) {
      logFail('BLE', 'Loi gui $cmd: $e');
    }
  }

  /// Gửi ACK (xác nhận an toàn)
  Future<void> sendAck() => sendCommand('ACK');

  /// Gửi SOS (cứu hộ khẩn cấp)
  Future<void> sendSos() => sendCommand('SOS');

  /// Gửi TEST_IMPACT (giả lập va chạm để kiểm tra)
  Future<void> sendTestImpact() => sendCommand('TEST_IMPACT');

  /// Dừng stream dữ liệu
  Future<void> sendStop() => sendCommand('STOP');

  /// Xử lý dữ liệu nhận được từ mũ (có buffer cho dữ liệu phân mảnh)
  void _onDataReceived(List<int> data) {
    if (data.isEmpty) return;

    final rawStr = String.fromCharCodes(data);
    logRx(
      'BLE',
      'RX ${data.length}B: ${rawStr.length > 80 ? '${rawStr.substring(0, 80)}...' : rawStr}',
    );

    try {
      _buffer += utf8.decode(data);

      while (true) {
        final nlIdx = _buffer.indexOf('\n');
        if (nlIdx == -1) break;

        final line = _buffer.substring(0, nlIdx).trim();
        _buffer = _buffer.substring(nlIdx + 1);

        if (line.isNotEmpty && line.startsWith('{')) {
          _tryParseJson(line);
        }
      }

      if (_buffer.length > 8192) {
        logWarn('BLE', 'Buffer qua dai (${_buffer.length}B), reset');
        _buffer = '';
      }
    } catch (e) {
      logFail('BLE', 'Loi decode buffer: $e');
      incrementParseError();
      _buffer = '';
    }
  }

  void _tryParseJson(String json) {
    try {
      startTimer('parse_json');
      _latestData = TelemetryData.fromJson(json);
      final parseMs = stopTimer('parse_json');
      _updateHeartbeat();
      incrementTelemetry();
      notifyListeners();
      logDebug(
        'BLE',
        'OK: peak_g=${_latestData?.impact?.peakG.toStringAsFixed(2) ?? "?"} ai_p=${_latestData?.impact?.aiP.toStringAsFixed(3) ?? "?"} (${parseMs.toStringAsFixed(1)}ms)',
      );
    } catch (e) {
      incrementParseError();
      logFail('BLE', 'Parse JSON loi: $e');
      logDebug(
        'BLE',
        'Raw: ${json.length > 100 ? '${json.substring(0, 100)}...' : json}',
      );
    }
  }

  /// Ngắt kết nối
  Future<void> disconnect() async {
    stopAutoReconnect();
    gpsFallback.dispose();
    await sendStop();
    await _txSubscription?.cancel();
    _txSubscription = null;
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
    _txChar = null;
    _rxChar = null;
    _latestData = null;
    _state = BleConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    stopAutoReconnect();
    gpsFallback.dispose();
    disconnect();
    super.dispose();
  }
}
