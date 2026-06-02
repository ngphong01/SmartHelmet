import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Foreground Service — giữ app sống khi màn hình tắt
/// Hiển thị notification cố định "Mũ thông minh đang hoạt động"
class ForegroundService {
  static bool _initialized = false;

  /// Khởi tạo foreground service (gọi 1 lần trong main)
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'smart_helmet_channel',
        channelName: 'Mũ Bảo Hiểm Thông Minh',
        channelDescription: 'Giám sát kết nối BLE và cảnh báo va chạm',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Bắt đầu foreground service
  static Future<bool> start() async {
    // Kích hoạt wake lock giữ CPU
    await WakelockPlus.enable();

    final result = await FlutterForegroundTask.startService(
      notificationTitle: '🪖 Mũ Bảo Hiểm Thông Minh',
      notificationText: 'Đang giám sát kết nối BLE...',
      notificationButtons: [
        const NotificationButton(id: 'btn_stop', text: 'Dừng'),
      ],
      callback: _onForegroundTaskCallback,
    );

    return result is ServiceRequestSuccess;
  }

  /// Dừng foreground service
  static Future<bool> stop() async {
    await WakelockPlus.disable();
    return await FlutterForegroundTask.stopService();
  }

  /// Kiểm tra service đang chạy không
  static Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }

  /// Callback chạy trong isolate riêng của foreground service
  @pragma('vm:entry-point')
  static void _onForegroundTaskCallback() {
    FlutterForegroundTask.setTaskHandler(_TaskHandler());
  }
}

/// Task handler cho foreground service
class _TaskHandler extends TaskHandler {
  @override
  Future<void> onStart(
    DateTime timestamp,
    TaskStoppedCallback? onStopped,
  ) async {
    debugPrint('[Foreground] Service started at $timestamp');
  }

  @override
  Future<void> onRepeatEvent(
    DateTime timestamp,
    TaskStoppedCallback? onStopped,
  ) async {
    // Cập nhật notification text mỗi 5s
    await FlutterForegroundTask.updateService(
      notificationTitle: '🪖 Mũ Bảo Hiểm Thông Minh',
      notificationText:
          'Đang hoạt động — ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  Future<void> onDestroy(
    DateTime timestamp,
    TaskStoppedCallback? onStopped,
  ) async {
    debugPrint('[Foreground] Service destroyed at $timestamp');
  }

  @override
  void onReceiveData(Object data) {
    // Nhận data từ main isolate
    debugPrint('[Foreground] Received: $data');
  }

  @override
  Future<void> onNotificationButtonPressed(String id) async {
    if (id == 'btn_stop') {
      await FlutterForegroundTask.stopService();
    }
  }
}
