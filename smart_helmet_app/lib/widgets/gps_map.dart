import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/telemetry_data.dart';

class GpsMapWidget extends StatelessWidget {
  final TelemetryData? data;
  final double height;
  const GpsMapWidget({super.key, this.data, this.height = 260});

  @override
  Widget build(BuildContext context) {
    final hasGps = data?.hasGps ?? false;
    final center = hasGps
        ? LatLng(data!.gps!.lat, data!.gps!.lon)
        : const LatLng(21.0278, 105.8342);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withAlpha(12)),
        ),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: hasGps ? 15.0 : 12.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.smarthelmet.app',
                ),
                if (hasGps)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(data!.gps!.lat, data!.gps!.lon),
                        width: 56,
                        height: 56,
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.motorcycle,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            // Glass overlay top-right
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black.withAlpha(150),
                  border: Border.all(color: Colors.white.withAlpha(30)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.gps_fixed,
                      color: hasGps ? const Color(0xFF00FF88) : Colors.red,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      hasGps ? 'GPS OK' : 'Đang tìm...',
                      style: TextStyle(
                        color: hasGps ? const Color(0xFF00FF88) : Colors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
