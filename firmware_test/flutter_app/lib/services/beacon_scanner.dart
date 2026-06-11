import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Quét BLE Emergency Beacon từ mũ bảo hiểm gần đó.
/// KHÔNG cần ghép đôi.
class BeaconScanner {
  static const String sosDeviceName = 'SOS-SmartHelmet';
  static const String emergencyUuid = '0000e911-0000-1000-8000-00805f9b34fb';

  final bool filterByService;
  BeaconScanner({this.filterByService = true});

  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _scanning = false;

  void Function(EmergencyBeacon beacon)? onEmergencyDetected;

  Future<void> start() async {
    if (_scanning) return;
    _scanning = true;
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {}

    _scanSub = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (e) => debugPrint('[BEACON] Loi scan: $e'),
    );

    try {
      await FlutterBluePlus.startScan(
        withServices: filterByService ? [Guid(emergencyUuid)] : const <Guid>[],
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: false,
      );
    } catch (e) {
      debugPrint('[BEACON] startScan that bai: $e');
      _scanning = false;
      await _scanSub?.cancel();
      _scanSub = null;
      rethrow;
    }
    debugPrint(
        '[BEACON] Scanner bat dau quet (filterByService=$filterByService)...');
  }

  void _onScanResults(List<ScanResult> results) {
    for (final r in results) {
      final name = r.device.platformName.isNotEmpty
          ? r.device.platformName
          : r.advertisementData.advName;
      if (name != sosDeviceName) continue;

      final beacon = _parseManufacturerData(
        r.advertisementData.manufacturerData,
        r.rssi,
      );
      if (beacon != null) {
        debugPrint(
            '[BEACON] SOS! GPS=${beacon.lat},${beacon.lon} rssi=${beacon.rssi}');
        onEmergencyDetected?.call(beacon);
      }
    }
  }

  Future<void> stop() async {
    _scanning = false;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {}
  }

  EmergencyBeacon? _parseManufacturerData(
    Map<int, List<int>> mfgData,
    int rssi,
  ) {
    if (mfgData.isEmpty) return null;
    final List<int> raw = mfgData.values.first;
    if (raw.length < 20) return null;

    try {
      final data = Uint8List.fromList(raw);
      final buf = ByteData.sublistView(data);

      final lat = buf.getFloat32(0, Endian.little);
      final lon = buf.getFloat32(4, Endian.little);
      final peakG = buf.getFloat32(8, Endian.little);
      final aiProb = buf.getFloat32(12, Endian.little);
      final isFall = data[16] == 1;
      final sats = data[17];

      int sum = 0;
      for (int i = 0; i < 18; i++) {
        sum += data[i];
      }
      final cs = (data[18] & 0xFF) | ((data[19] & 0xFF) << 8);
      if ((sum & 0xFFFF) != cs) return null;

      return EmergencyBeacon(
        lat: lat,
        lon: lon,
        peakG: peakG,
        aiProbability: aiProb,
        isFall: isFall,
        satellites: sats,
        rssi: rssi,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    stop();
  }
}

/// Dữ liệu beacon giải mã
class EmergencyBeacon {
  final double lat;
  final double lon;
  final double peakG;
  final double aiProbability;
  final bool isFall;
  final int satellites;
  final int rssi;

  EmergencyBeacon({
    required this.lat,
    required this.lon,
    required this.peakG,
    required this.aiProbability,
    required this.isFall,
    required this.satellites,
    required this.rssi,
  });

  @override
  String toString() {
    return 'EmergencyBeacon(lat=$lat, lon=$lon, peak=${peakG}g, '
        'AI=${(aiProbability * 100).toStringAsFixed(0)}%, '
        'fall=$isFall, sats=$satellites)';
  }
}
