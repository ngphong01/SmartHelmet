import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' as pp;

// ============================================================
// APP LOGGER — Unified logging for SmartHelmet Flutter App
// ============================================================
// Format: [HH:mm:ss.SSS][TAG][LEVEL] emoji message
// Features: timestamp, levels, file export, latency tracker,
//            stats summary, GPS state tracker
// ============================================================

// --- Log Levels ---
enum AppLogLevel { ERROR, WARN, INFO, DEBUG }

AppLogLevel _currentLevel = AppLogLevel.INFO;

// --- File export ---
File? _logFile;
bool _fileExportEnabled = false;

// --- Latency tracker ---
final Map<String, int> _timers = {};

// --- Stats ---
int _telemetryCount = 0;
int _parseErrorCount = 0;
int _impactCount = 0;
int _fallCount = 0;
int _ackCount = 0;
int _sosCount = 0;
int _disconnectCount = 0;
int _reconnectCount = 0;
DateTime _statsStart = DateTime.now();
DateTime _lastStatsTime = DateTime.now();
Timer? _statsTimer;

// ============================================================
// CORE
// ============================================================

String _ts() {
  final n = DateTime.now();
  return '${n.hour.toString().padLeft(2, '0')}:'
      '${n.minute.toString().padLeft(2, '0')}:'
      '${n.second.toString().padLeft(2, '0')}.'
      '${n.millisecond.toString().padLeft(3, '0')}';
}

void _write(String line) {
  debugPrint(line);
  if (_fileExportEnabled && _logFile != null) {
    try {
      _logFile!.writeAsStringSync(
        '$line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }
}

// ============================================================
// PUBLIC MACROS
// ============================================================

void logError(String tag, String msg) {
  if (_currentLevel.index >= AppLogLevel.ERROR.index) {
    _write('[\x1b[31m${_ts()}\x1b[0m][$tag][ERROR] ❌ $msg');
  }
}

void logWarn(String tag, String msg) {
  if (_currentLevel.index >= AppLogLevel.WARN.index) {
    _write('[\x1b[33m${_ts()}\x1b[0m][$tag][WARN]  ⚠️ $msg');
  }
}

void logInfo(String tag, String msg) {
  if (_currentLevel.index >= AppLogLevel.INFO.index) {
    _write('[\x1b[36m${_ts()}\x1b[0m][$tag][INFO]  $msg');
  }
}

void logDebug(String tag, String msg) {
  if (_currentLevel.index >= AppLogLevel.DEBUG.index) {
    _write('[\x1b[90m${_ts()}\x1b[0m][$tag][DEBUG] $msg');
  }
}

// --- Convenience with emoji ---
void logOk(String tag, String msg) => logInfo(tag, '✅ $msg');
void logFail(String tag, String msg) => logError(tag, '$msg');
void logRx(String tag, String msg) => logDebug(tag, '📥 $msg');
void logTx(String tag, String msg) => logDebug(tag, '📤 $msg');
void logRetry(String tag, String msg) => logWarn(tag, '🔄 $msg');
void logImpact(String tag, String msg) => logWarn(tag, '🚨 $msg');

/// Log banner — always visible
void logBanner(String msg) => _write('\n\x1b[1;31m$msg\x1b[0m\n');

// ============================================================
// CONFIG
// ============================================================

void setLogLevel(AppLogLevel level) {
  _currentLevel = level;
  logInfo('LOGGER', 'Log level: ${level.name}');
}

AppLogLevel getLogLevel() => _currentLevel;

// ============================================================
// FILE EXPORT
// ============================================================

Future<void> enableFileExport() async {
  try {
    final dir = await pp.getApplicationDocumentsDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    _logFile = File('${dir.path}/smarthelmet_$ts.log');
    await _logFile!.create();
    _fileExportEnabled = true;
    logInfo('LOGGER', '📁 File export: ${_logFile!.path}');
    _write('=== SmartHelmet App Log ===');
    _write('=== Started: $ts ===');
  } catch (e) {
    debugPrint('Cannot enable file export: $e');
  }
}

String? getLogFilePath() => _logFile?.path;

// ============================================================
// BOOT INFO
// ============================================================

void logBootInfo({
  required String version,
  required String buildMode,
  required String platform,
  required String device,
  required String locale,
}) {
  _write('\n============================================================');
  _write('    MU BAO HIEM THONG MINH - SmartHelmet App');
  _write('    Version: $version ($buildMode)');
  _write('    Platform: $platform');
  _write('    Device: $device');
  _write('    Locale: $locale');
  _write('============================================================\n');
}

// ============================================================
// PERMISSION LOGGING
// ============================================================

void logPermission(String permission, bool granted, {String? detail}) {
  final icon = granted ? '✅' : '❌';
  final detailStr = detail != null ? ' ($detail)' : '';
  if (granted) {
    logOk('PERM', '$permission: GRANTED$detailStr');
  } else {
    logFail('PERM', '$permission: DENIED$detailStr');
  }
}

// ============================================================
// STATS SUMMARY (gọi mỗi 60s)
// ============================================================

void startStatsTimer() {
  _statsStart = DateTime.now();
  _lastStatsTime = DateTime.now();
  _statsTimer?.cancel();
  _statsTimer = Timer.periodic(const Duration(seconds: 60), (_) {
    _printStats();
  });
}

void stopStatsTimer() {
  _statsTimer?.cancel();
  _statsTimer = null;
}

void incrementTelemetry() => _telemetryCount++;
void incrementParseError() => _parseErrorCount++;
void incrementImpact() => _impactCount++;
void incrementFall() => _fallCount++;
void incrementAck() => _ackCount++;
void incrementSos() => _sosCount++;
void incrementDisconnect() => _disconnectCount++;
void incrementReconnect() => _reconnectCount++;

void _printStats() {
  final elapsed = DateTime.now().difference(_statsStart);
  final mins = elapsed.inMinutes;
  final secs = elapsed.inSeconds % 60;

  var uptime = '';
  if (mins > 0)
    uptime = '${mins}ph ${secs}s';
  else
    uptime = '${secs}s';

  _write('\n[${_ts()}][STATS][INFO] ===== $uptime qua =====');
  _write(
    '[${_ts()}][STATS][INFO] Telemetry: $_telemetryCount pkt, $_parseErrorCount errors',
  );
  _write(
    '[${_ts()}][STATS][INFO] Events: impact=$_impactCount fall=$_fallCount ack=$_ackCount sos=$_sosCount',
  );
  _write(
    '[${_ts()}][STATS][INFO] BLE: $_disconnectCount disconnects, $_reconnectCount reconnects',
  );
  _write('[${_ts()}][STATS][INFO] ====================\n');

  // Reset counters
  _telemetryCount = 0;
  _parseErrorCount = 0;
  _disconnectCount = 0;
  _reconnectCount = 0;
}

// ============================================================
// LATENCY TRACKER
// ============================================================

void startTimer(String name) {
  _timers[name] = DateTime.now().microsecondsSinceEpoch;
}

double stopTimer(String name) {
  final start = _timers.remove(name);
  if (start == null) return -1;
  final elapsedUs = DateTime.now().microsecondsSinceEpoch - start;
  final ms = elapsedUs / 1000.0;
  logDebug('PERF', '⏱️ $name: ${ms.toStringAsFixed(1)}ms');
  return ms;
}

// ============================================================
// BLE STATE MACHINE LOG
// ============================================================

void logBleState(String from, String to, {String? detail}) {
  final msg = 'State: $from → $to${detail != null ? ' ($detail)' : ''}';
  if (to == 'connected' || to == 'ready' || to == 'streaming') {
    logOk('BLE', msg);
  } else if (to == 'disconnected' || to == 'timeout') {
    logFail('BLE', msg);
  } else {
    logInfo('BLE', msg);
  }
}

// ============================================================
// GPS STATE LOG
// ============================================================

String _gpsState = 'unknown';

void logGpsState(String newState, {String? reason}) {
  final rsn = reason != null ? ' ($reason)' : '';
  if (newState == _gpsState) return;
  logInfo('GPS', 'State: $_gpsState → $newState$rsn');
  _gpsState = newState;
}

// ============================================================
// LIFECYCLE LOG
// ============================================================

void logLifecycle(String state) {
  logInfo('LIFE', 'App state: $state');
}

// ============================================================
// RECONNECT BACKOFF LOG
// ============================================================

void logReconnectAttempt(int attempt, int delaySec, {String? result}) {
  if (result != null) {
    if (result.contains('OK') || result.contains('thanh cong')) {
      logOk('BLE', 'Reconnect try $attempt: $result');
    } else {
      logRetry('BLE', 'Reconnect try $attempt: $result (delay=${delaySec}s)');
    }
  } else {
    logRetry('BLE', 'Auto-reconnect try $attempt, delay=${delaySec}s');
  }
}
