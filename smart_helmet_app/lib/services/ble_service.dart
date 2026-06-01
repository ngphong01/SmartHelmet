import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/telemetry_data.dart';

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
      // Dừng scan cũ nếu có
      await FlutterBluePlus.stopScan();

      BluetoothDevice? found;

      // ─── Cách 1: Kiểm tra thiết bị đã paired ──────────────────
      debugPrint('[BLE] 🔍 Kiểm tra thiết bị đã paired...');
      final paired = await FlutterBluePlus.systemDevices([]);
      debugPrint('[BLE] Có ${paired.length} thiết bị paired');
      for (final d in paired) {
        debugPrint('[BLE]   → ${d.platformName} | ${d.remoteId}');
        try {
          await d.connect(
            autoConnect: false,
            timeout: const Duration(seconds: 5),
          );
          await d.discoverServices();
          for (final srv in d.servicesList) {
            if (srv.uuid.toString().toLowerCase() == _serviceUuid) {
              found = d;
              debugPrint('[BLE] ✅ Tìm thấy SmartHelmet trong paired!');
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
        debugPrint('[BLE] 🔍 Bắt đầu scan BLE (không filter)...');
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

        await for (final results in FlutterBluePlus.scanResults) {
          debugPrint('[BLE] 📡 Tìm thấy ${results.length} thiết bị BLE');
          for (final r in results) {
            final name = (r.device.platformName).toUpperCase();
            final advName = (r.advertisementData.advName ?? '').toUpperCase();
            final mac = r.device.remoteId.toString().toUpperCase();
            debugPrint(
              '  → Tên: "$name" | Adv: "$advName" | MAC: $mac | RSSI: ${r.rssi}',
            );

            // So sánh không phân biệt hoa thường
            if (name.contains('SMARTHELMET') ||
                advName.contains('SMARTHELMET') ||
                mac == '80:F3:DA:A9:A8:9A') {
              found = r.device;
              debugPrint('[BLE] ✅ Tìm thấy SmartHelmet! $name | $mac');
              break;
            }
          }
          if (found != null) break;
        }

        await FlutterBluePlus.stopScan();
      }

      if (found == null) {
        debugPrint('[BLE] ❌ Không tìm thấy SmartHelmet');
        _state = BleConnectionState.disconnected;
        notifyListeners();
        return false;
      }

      _state = BleConnectionState.connecting;
      notifyListeners();

      _device = found;
      // Chỉ connect nếu chưa connect
      try {
        if (_device!.isDisconnected) {
          await _device!.connect(autoConnect: false);
        }
        await _device!.discoverServices();
      } catch (e) {
        debugPrint('[BLE] Lỗi connect device: $e');
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
        debugPrint('[BLE] ❌ Không tìm thấy UART Service');
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
        debugPrint('[BLE] ❌ Không tìm thấy TX/RX characteristic');
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

      debugPrint('[BLE] ✅ Đã kết nối và bắt đầu nhận dữ liệu!');
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
      await _rxChar!.write(utf8.encode(cmd), withoutResponse: false);
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

  /// Xử lý dữ liệu nhận được từ mũ (có buffer cho dữ liệu phân mảnh)
  void _onDataReceived(List<int> data) {
    // DEBUG: Log raw để xem data có vào không
    debugPrint(
      '[BLE] RAW (${data.length}B): ${String.fromCharCodes(data).substring(0, data.length < 200 ? data.length : 200)}',
    );

    try {
      _buffer += utf8.decode(data);
      debugPrint('[BLE] BUFFER length: ${_buffer.length}');

      // Parse JSON theo \n hoặc theo cặp dấu {} hoàn chỉnh
      while (true) {
        // Cách 1: tìm \n
        final nlIdx = _buffer.indexOf('\n');
        final useNewline = nlIdx != -1;

        if (useNewline) {
          final line = _buffer.substring(0, nlIdx).trim();
          _buffer = _buffer.substring(nlIdx + 1);
          debugPrint(
            '[BLE] 📋 Line found (${line.length} chars): ${line.substring(0, line.length < 150 ? line.length : 150)}',
          );
          if (line.isNotEmpty && line.startsWith('{')) {
            _tryParseJson(line);
          } else {
            debugPrint(
              '[BLE] ⚠️ Line skipped (starts with "${line.isNotEmpty ? line[0] : "empty"}")',
            );
          }
          continue;
        }

        // Cách 2: tìm JSON hoàn chỉnh bằng dấu {}
        final start = _buffer.indexOf('{');
        if (start == -1) {
          _buffer = '';
          break;
        }
        if (start > 0) _buffer = _buffer.substring(start);

        int depth = 0, end = -1;
        for (int i = 0; i < _buffer.length; i++) {
          if (_buffer[i] == '{')
            depth++;
          else if (_buffer[i] == '}') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
        if (end == -1) break; // Chưa có JSON hoàn chỉnh

        final json = _buffer.substring(0, end + 1);
        _buffer = _buffer.substring(end + 1);
        _tryParseJson(json);
      }

      if (_buffer.length > 4096)
        _buffer = _buffer.substring(_buffer.length - 2048);
    } catch (e) {
      debugPrint('[BLE] Lỗi decode: $e');
      _buffer = '';
    }
  }

  void _tryParseJson(String json) {
    try {
      _latestData = TelemetryData.fromJson(json);
      notifyListeners();
      debugPrint(
        '[BLE] OK: ${json.length > 80 ? '${json.substring(0, 80)}...' : json}',
      );
    } catch (e) {
      debugPrint('[BLE] Lỗi parse JSON: $e\n  Data: ${json.substring(0, 100)}');
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
