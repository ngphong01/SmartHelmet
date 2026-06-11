import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import 'services/ble_service.dart';
import 'services/foreground_service.dart';
import 'screens/home_screen.dart';
import 'screens/impact_alert_screen.dart';
import 'utils/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Boot info log
  logBootInfo(
    version: '1.0.0+1',
    buildMode: kDebugMode
        ? 'debug'
        : kReleaseMode
        ? 'release'
        : 'profile',
    platform: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    device: 'Android', // Will be updated with actual device info
    locale: 'vi_VN',
  );

  // Permission logging
  logPermission('Bluetooth', true);
  logPermission('Location', true, detail: 'precise');
  logPermission('Notification', true);
  logPermission('Battery optimization', true, detail: 'WHITELISTED');

  // Start stats timer
  startStatsTimer();

  // Lock to portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Init foreground service
  ForegroundService.init();

  runApp(const SmartHelmetApp());
}

class SmartHelmetApp extends StatefulWidget {
  const SmartHelmetApp({super.key});

  @override
  State<SmartHelmetApp> createState() => _SmartHelmetAppState();
}

class _SmartHelmetAppState extends State<SmartHelmetApp>
    with WidgetsBindingObserver {
  final BleService _bleService = BleService();
  bool _showingImpact = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bleService.addListener(_onBleChanged);
    logInfo('UI', 'HomeScreen mounted');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        logLifecycle('paused → resumed');
        break;
      case AppLifecycleState.paused:
        logLifecycle('resumed → paused (user nhan home)');
        break;
      case AppLifecycleState.inactive:
        logLifecycle('inactive');
        break;
      case AppLifecycleState.detached:
        logLifecycle('detached');
        break;
      default:
        break;
    }
  }

  void _onBleChanged() {
    final data = _bleService.latestData;
    if (data != null && data.isImpact && !_showingImpact) {
      _showingImpact = true;
      _showImpactAlert(data);
    }
  }

  void _showImpactAlert(dynamic data) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) =>
                ImpactAlertScreen(data: data, bleService: _bleService),
          ),
        )
        .then((_) {
          _showingImpact = false;
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bleService.removeListener(_onBleChanged);
    _bleService.dispose();
    stopStatsTimer();
    logInfo('APP', 'App disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _bleService,
      child: MaterialApp(
        title: 'SmartHelmet',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF0F172A),
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          colorScheme: const ColorScheme.dark(
            primary: Colors.blue,
            secondary: Colors.blueAccent,
            surface: Color(0xFF1E293B),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0F172A),
            elevation: 0,
          ),
          fontFamily: 'Roboto',
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
