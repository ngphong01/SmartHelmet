import 'dart:convert';

class TelemetryData {
  final String type;
  final String helmetId;
  final GpsData? gps;
  final ImuData? imu; // v3: pitch, roll, angular_velocity
  final ImpactData? impact;
  final StateData? state; // v3: ride_state, fall_detected
  final String? firmwareVersion;
  final DateTime? utcTime;
  final int? timestampMs;

  TelemetryData({
    required this.type,
    required this.helmetId,
    this.gps,
    this.imu,
    this.impact,
    this.state,
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
      imu: map['imu'] != null ? ImuData.fromJson(map['imu']) : null,
      impact: map['impact'] != null ? ImpactData.fromJson(map['impact']) : null,
      state: map['state'] != null ? StateData.fromJson(map['state']) : null,
      firmwareVersion: map['firmware']?['version'],
      utcTime: map['time']?['utc'] != null
          ? DateTime.tryParse(map['time']['utc'])
          : null,
      timestampMs: map['ts'] != null
          ? int.tryParse(map['ts'].toString())
          : null,
    );
  }

  /// GPS được coi là hợp lệ khi có tọa độ khác 0 VÀ có ít nhất 3 vệ tinh
  bool get hasGps =>
      gps != null && gps!.lat != 0.0 && gps!.lon != 0.0 && gps!.satellites >= 3;
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
  final String? eventType; // v3: "none", "impact_detected", "fall_detected"

  ImpactData({
    required this.detected,
    required this.aiP,
    required this.peakG,
    required this.confidence,
    this.eventType,
  });

  bool get isFall => eventType == 'fall_detected';

  factory ImpactData.fromJson(Map<String, dynamic> json) {
    return ImpactData(
      detected: json['detected'] == true || json['detected'] == 'true',
      aiP: (json['ai_p'] as num?)?.toDouble() ?? 0.0,
      peakG: (json['peak_g'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      eventType: json['event_type'] as String?,
    );
  }
}

// ============================================================
// V3: IMU data (pitch, roll, angular velocity)
// ============================================================
class ImuData {
  final double pitchDeg;
  final double rollDeg;
  final double angularVelDps;

  ImuData({
    required this.pitchDeg,
    required this.rollDeg,
    required this.angularVelDps,
  });

  factory ImuData.fromJson(Map<String, dynamic> json) {
    return ImuData(
      pitchDeg: (json['pitch_deg'] as num?)?.toDouble() ?? 0.0,
      rollDeg: (json['roll_deg'] as num?)?.toDouble() ?? 0.0,
      angularVelDps: (json['angular_vel_dps'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ============================================================
// V3: State data (ride state, fall detected, uptime)
// ============================================================
class StateData {
  final String rideState; // IDLE, RIDING, IMPACT, FALLEN, SOS
  final bool fallDetected;
  final int uptimeSeconds;

  StateData({
    required this.rideState,
    required this.fallDetected,
    required this.uptimeSeconds,
  });

  bool get isEmergency =>
      rideState == 'IMPACT' || rideState == 'FALLEN' || rideState == 'SOS';

  factory StateData.fromJson(Map<String, dynamic> json) {
    return StateData(
      rideState: json['ride_state'] as String? ?? 'IDLE',
      fallDetected:
          json['fall_detected'] == true || json['fall_detected'] == 'true',
      uptimeSeconds: (json['uptime_s'] as num?)?.toInt() ?? 0,
    );
  }
}
