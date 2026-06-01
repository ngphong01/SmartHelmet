import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class ConnectionStatusBar extends StatelessWidget {
  final BleConnectionState state;
  const ConnectionStatusBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      BleConnectionState.disconnected => ('Chưa kết nối', Colors.white38, Icons.bluetooth_disabled),
      BleConnectionState.scanning     => ('Đang quét...', const Color(0xFFF59E0B), Icons.bluetooth_searching),
      BleConnectionState.connecting   => ('Đang kết nối...', const Color(0xFFF59E0B), Icons.bluetooth),
      BleConnectionState.connected    => ('ĐÃ KẾT NỐI', const Color(0xFF00FF88), Icons.bluetooth),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60)),
        gradient: LinearGradient(
            colors: [color.withAlpha(20), color.withAlpha(5)]),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: color,
            boxShadow: [BoxShadow(color: color.withAlpha(120), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(color: color, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1)),
      ]),
    );
  }
}
