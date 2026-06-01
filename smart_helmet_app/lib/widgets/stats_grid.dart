import 'package:flutter/material.dart';
import '../models/telemetry_data.dart';

class StatsGrid extends StatelessWidget {
  final TelemetryData? data;
  const StatsGrid({super.key, this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _GlassStat(
                Icons.speed,
                'Đỉnh G',
                data?.impact?.peakG.toStringAsFixed(2) ?? '--',
                'g',
                [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GlassStat(
                Icons.psychology,
                'AI Dự Đoán',
                data?.impact != null
                    ? '${(data!.impact!.aiP * 100).toStringAsFixed(1)}'
                    : '--',
                '%',
                [const Color(0xFFA855F7), const Color(0xFF6366F1)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _GlassStat(
                Icons.satellite_alt,
                'Vệ Tinh',
                data?.gps?.satellites.toString() ?? '--',
                '',
                [const Color(0xFF06B6D4), const Color(0xFF0EA5E9)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GlassStat(
                Icons.speed_outlined,
                'Tốc Độ',
                data?.gps?.speedKmh.toStringAsFixed(1) ?? '--',
                'km/h',
                [const Color(0xFF10B981), const Color(0xFF34D399)],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GlassStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final List<Color> gradient;

  const _GlassStat(this.icon, this.label, this.value, this.unit, this.gradient);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(12)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withAlpha(10), Colors.white.withAlpha(3)],
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(colors: gradient),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 11),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    unit,
                    style: TextStyle(
                      color: Colors.white.withAlpha(100),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
