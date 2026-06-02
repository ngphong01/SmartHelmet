import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// GPS Fallback Service — dùng GPS điện thoại khi NEO-6M yếu
/// 3 chế độ: Auto / NEO-6M Only / Phone GPS Only
enum GpsSource { neo6m, phone, none }

enum GpsMode { auto, neo6mOnly, phoneOnly }

class GpsFallbackService {
  GpsMode _mode = GpsMode.auto;
  GpsSource _currentSource = GpsSource.none;
  Position? _lastPosition;
  StreamSubscription<Position>? _positionStream;

  GpsSource get currentSource => _currentSource;
  Position? get lastPosition => _lastPosition;
  GpsMode get mode => _mode;

  /// Khởi tạo + xin quyền GPS
  Future<bool> init() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final result = await Geolocator.requestPermission();
      if (result != LocationPermission.whileInUse &&
          result != LocationPermission.always) {
        return false;
      }
    }
    return true;
  }

  /// Cập nhật chế độ
  void setMode(GpsMode mode) {
    _mode = mode;
    if (mode == GpsMode.phoneOnly) {
      _startPhoneGps();
    } else {
      _stopPhoneGps();
    }
  }

  /// Quyết định nguồn GPS dựa trên dữ liệu từ mũ
  /// helmetSatellites: số vệ tinh NEO-6M
  /// helmetHdop: HDOP từ NEO-6M
  GpsSource evaluate(double? helmetSatellites, double? helmetHdop) {
    switch (_mode) {
      case GpsMode.neo6mOnly:
        _stopPhoneGps();
        _currentSource = GpsSource.neo6m;
        break;

      case GpsMode.phoneOnly:
        _startPhoneGps();
        _currentSource = GpsSource.phone;
        break;

      case GpsMode.auto:
        final sats = helmetSatellites ?? 0;
        final hdop = helmetHdop ?? 99.9;

        if (sats >= 4 && hdop < 5.0) {
          // NEO-6M tốt → dùng mũ
          _stopPhoneGps();
          _currentSource = GpsSource.neo6m;
        } else if (sats < 3 || hdop > 5.0) {
          // NEO-6M yếu → dùng phone GPS
          _startPhoneGps();
          _currentSource = GpsSource.phone;
        } else {
          _currentSource = GpsSource.neo6m;
        }
        break;
    }
    return _currentSource;
  }

  void _startPhoneGps() {
    if (_positionStream != null) return;
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // cập nhật mỗi 5m
          ),
        ).listen((pos) {
          _lastPosition = pos;
        });
  }

  void _stopPhoneGps() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  /// Lấy tọa độ hiện tại (từ phone hoặc null nếu dùng NEO-6M)
  Position? getPhonePosition() => _lastPosition;

  void dispose() {
    _stopPhoneGps();
  }
}
