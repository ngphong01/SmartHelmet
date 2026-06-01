import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/telemetry_data.dart';

/// Service UUID & Characteristic UUIDs cho Nordic UART Service
const String _serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String _charTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // NOTIFY (mũ → app)
const String _charRxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // WRITE  (app → mũ)

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
}

class BleService extends ChangeNotifier {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  BleConnectionState _state = BleConnectionState.disconnected;
  TelemetryData? _latestData;
  StreamSubscription? _txSubscription;

  // Getters
  BleConnectionState get state => _state;
  TelemetryData? get latestData => _latestData;
  bool get isConnected => _state == BleConnectionState.connected;

  /// Quét và kết nối tới thiết bị có tên "SmartHelmet"
  Future<bool> connect() async {
    if (_state == BleConnectionState.connected) return true;

    _state = BleConnectionState.scanning;
    notifyListeners();

    try {
      // Bắt đầu quét BLE
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
      );

      BluetoothDevice? found;
      await for (final result in FlutterBluePlus.scanResults) {
        for (final r in result) {
          if (r.device.platformName.contains('SmartHelmet') ||
              r.advertisementData.advName == 'SmartHelmet') {
            found = r.device;
            break;
          }
        }
        if (found != null) break;
      }

      await FlutterBluePlus.stopScan();

      if (found == null) {
        _state = BleConnectionState.disconnected;
        notifyListeners();
        return false;
      }

      _state = BleConnectionState.connecting;
      notifyListeners();

      _device = found;
      await _device!.connect(autoConnect: false);
      await _device!.discoverServices();

      // Tìm Nordic UART Service
      BluetoothService? uartService;
      for (final srv in _device!.servicesList) {
        if (srv.uuid.toString().toLowerCase() == _serviceUuid) {
          uartService = srv;
          break;
        }
      }

      if (uartService == null) {
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

      return true;
    } catch (e) {
      debugPrint('BLE connect error: $e');
      _state = BleConnectionState.disconnected;
      notifyListeners();
      return false;
    }
  }

  /// Gửi lệnh qua RX characteristic
  Future<void> sendCommand(String cmd) async {
    if (_rxChar == null) return;
    try {
      await _rxChar!.write(utf8.encode(cmd), withoutResponse: true);
      debugPrint('[BLE] Gửi: $cmd');
    } catch (e) {
      debugPrint('[BLE] Lỗi gửi: $e');
    }
  }

  /// Gửi ACK (xác nhận an toàn)
  Future<void> sendAck() => sendCommand('ACK');

  /// Gửi SOS (cứu hộ khẩn cấp)
  Future<void> sendSos() => sendCommand('SOS');

  /// Dừng stream dữ liệu
  Future<void> sendStop() => sendCommand('STOP');

  /// Xử lý dữ liệu nhận được từ mũ
  void _onDataReceived(List<int> data) {
    try {
      final text = utf8.decode(data);
      _latestData = TelemetryData.fromJson(text);
      notifyListeners();

      debugPrint('[BLE] Nhận: ${text.length > 100 ? '${text.substring(0, 100)}...' : text}');
    } catch (e) {
      debugPrint('[BLE] Lỗi parse JSON: $e');
    }
  }

  /// Ngắt kết nối
  Future<void> disconnect() async {
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
    disconnect();
    super.dispose();
  }
}
