import 'dart:convert';

class TelemetryData {
  final String type;
  final String helmetId;
  final GpsData? gps;
  final ImpactData? impact;
  final String? firmwareVersion;
  final DateTime? utcTime;
  final int? timestampMs;

  TelemetryData({
    required this.type,
    required this.helmetId,
    this.gps,
    this.impact,
    this.firmwareVersion,
    this.utcTime,
    this.timestampMs,
  });

  factory TelemetryData.fromJson(String jsonStr) {
    final map = json.decode(jsonStr) as Map<String, dynamic>;
    return TelemetryData(
      type: map['type'] ?? '',
      helmetId: map['helmet_id'] ?? '',
      gps: map['gps'] != null ? GpsData.fromJson(map['gps']) : null,
      impact: map['impact'] != null ? ImpactData.fromJson(map['impact']) : null,
      firmwareVersion: map['firmware']?['version'],
      utcTime: map['time']?['utc'] != null
          ? DateTime.tryParse(map['time']['utc'])
          : null,
      timestampMs: map['ts'] != null ? int.tryParse(map['ts'].toString()) : null,
    );
  }

  bool get hasGps => gps != null && gps!.lat != 0 && gps!.lon != 0;
  bool get isImpact => impact?.detected == true;
}

class GpsData {
  final double lat;
  final double lon;
  final double speedKmh;
  final int satellites;
  final double hdop;

  GpsData({
    required this.lat,
    required this.lon,
    required this.speedKmh,
    required this.satellites,
    required this.hdop,
  });

  factory GpsData.fromJson(Map<String, dynamic> json) {
    return GpsData(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      speedKmh: (json['speed_kmh'] as num?)?.toDouble() ?? 0.0,
      satellites: (json['satellites'] as num?)?.toInt() ?? 0,
      hdop: (json['hdop'] as num?)?.toDouble() ?? 99.9,
    );
  }
}

class ImpactData {
  final bool detected;
  final double aiP;
  final double peakG;
  final double confidence;

  ImpactData({
    required this.detected,
    required this.aiP,
    required this.peakG,
    required this.confidence,
  });

  factory ImpactData.fromJson(Map<String, dynamic> json) {
    return ImpactData(
      detected: json['detected'] == true || json['detected'] == 'true',
      aiP: (json['ai_p'] as num?)?.toDouble() ?? 0.0,
      peakG: (json['peak_g'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
