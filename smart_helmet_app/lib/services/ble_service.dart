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

        // === YÊU CẦU MTU 512 ĐỂ JSON 500 BYTE VỪA 1 GÓI ===
        try {
          final mtu = await _device!.requestMtu(512);
          debugPrint('[BLE] 📡 MTU negotiated: $mtu bytes');
        } catch (e) {
          debugPrint('[BLE] ⚠️ Không thể request MTU 512: $e');
          // Fallback: firmware sẽ tự chunk 180 byte
        }
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

  /// Gửi TEST_IMPACT (giả lập va chạm để kiểm tra)
  Future<void> sendTestImpact() => sendCommand('TEST_IMPACT');

  /// Dừng stream dữ liệu
  Future<void> sendStop() => sendCommand('STOP');

  /// Xử lý dữ liệu nhận được từ mũ (có buffer cho dữ liệu phân mảnh)
  void _onDataReceived(List<int> data) {
    if (data.isEmpty) return;

    // DEBUG: Log raw data
    final rawStr = String.fromCharCodes(data);
    debugPrint(
      '[BLE] 📥 RAW (${data.length}B): ${rawStr.length > 120 ? '${rawStr.substring(0, 120)}...' : rawStr}',
    );

    try {
      _buffer += utf8.decode(data);

      // Parse JSON theo \n delimiter
      while (true) {
        final nlIdx = _buffer.indexOf('\n');
        if (nlIdx == -1) break; // Chưa có delimiter → đợi thêm data

        final line = _buffer.substring(0, nlIdx).trim();
        _buffer = _buffer.substring(nlIdx + 1);

        debugPrint(
          '[BLE] 📋 Line (${line.length} chars): ${line.length > 120 ? '${line.substring(0, 120)}...' : line}',
        );

        if (line.isNotEmpty && line.startsWith('{')) {
          _tryParseJson(line);
        } else if (line.isNotEmpty) {
          debugPrint(
            '[BLE] ⚠️ Line không phải JSON, skip: "${line.length > 50 ? '${line.substring(0, 50)}...' : line}"',
          );
        }
      }

      // Giới hạn buffer tránh memory leak nếu data lỗi
      if (_buffer.length > 8192) {
        debugPrint('[BLE] ⚠️ Buffer quá dài (${_buffer.length}), reset');
        _buffer = '';
      }
    } catch (e) {
      debugPrint('[BLE] ❌ Lỗi decode buffer: $e');
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
