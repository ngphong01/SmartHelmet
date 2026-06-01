import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'screens/home_screen.dart';
import 'screens/impact_alert_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const SmartHelmetApp());
}

class SmartHelmetApp extends StatefulWidget {
  const SmartHelmetApp({super.key});

  @override
  State<SmartHelmetApp> createState() => _SmartHelmetAppState();
}

class _SmartHelmetAppState extends State<SmartHelmetApp> {
  final BleService _bleService = BleService();
  bool _showingImpact = false;

  @override
  void initState() {
    super.initState();
    _bleService.addListener(_onBleChanged);
  }

  void _onBleChanged() {
    final data = _bleService.latestData;
    if (data != null && data.isImpact && !_showingImpact) {
      _showingImpact = true;
      _showImpactAlert(data);
    }
  }

  void _showImpactAlert(dynamic data) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImpactAlertScreen(data: data, bleService: _bleService),
      ),
    ).then((_) {
      _showingImpact = false;
    });
  }

  @override
  void dispose() {
    _bleService.removeListener(_onBleChanged);
    _bleService.dispose();
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
