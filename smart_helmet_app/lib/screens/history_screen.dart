import 'package:flutter/material.dart';

/// History Screen — Lịch sử chuyến đi & cảnh báo
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Demo data
  final List<Map<String, dynamic>> _trips = [
    {
      'date': '02/06/2026',
      'time': '12:00',
      'distance': 2.4,
      'duration': 12,
      'speedAvg': 12.0,
      'speedMax': 35.0,
      'alerts': 0,
    },
    {
      'date': '01/06/2026',
      'time': '18:30',
      'distance': 5.1,
      'duration': 25,
      'speedAvg': 12.2,
      'speedMax': 42.0,
      'alerts': 1,
    },
    {
      'date': '01/06/2026',
      'time': '07:15',
      'distance': 3.8,
      'duration': 18,
      'speedAvg': 12.7,
      'speedMax': 38.0,
      'alerts': 0,
    },
    {
      'date': '28/05/2026',
      'time': '17:00',
      'distance': 8.2,
      'duration': 35,
      'speedAvg': 14.1,
      'speedMax': 45.0,
      'alerts': 2,
    },
  ];

  final List<Map<String, dynamic>> _alerts = [
    {
      'date': '01/06/2026 18:45',
      'type': 'impact',
      'peakG': 3.25,
      'aiP': 98.2,
      'location': 'Cầu Giấy, Hà Nội',
      'ack': true,
    },
    {
      'date': '28/05/2026 17:20',
      'type': 'fall',
      'peakG': 2.80,
      'aiP': 95.5,
      'pitch': 78.2,
      'location': 'Đống Đa, Hà Nội',
      'ack': true,
    },
    {
      'date': '25/05/2026 08:10',
      'type': 'impact',
      'peakG': 2.95,
      'aiP': 91.3,
      'location': 'Hoàn Kiếm, Hà Nội',
      'ack': false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('📜 Lịch sử'),
        backgroundColor: const Color(0xFF1E293B),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Chuyến đi', icon: Icon(Icons.route, size: 18)),
            Tab(text: 'Cảnh báo', icon: Icon(Icons.warning_amber, size: 18)),
            Tab(text: 'Thống kê', icon: Icon(Icons.bar_chart, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildTripsTab(), _buildAlertsTab(), _buildStatsTab()],
      ),
    );
  }

  // ─── TRIPS TAB ─────────────────────────────────────
  Widget _buildTripsTab() => ListView.builder(
    padding: const EdgeInsets.all(12),
    itemCount: _trips.length,
    itemBuilder: (_, i) {
      final t = _trips[i];
      final hasAlert = t['alerts'] > 0;
      return Card(
        color: const Color(0xFF1E293B),
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: hasAlert
                ? Colors.red.withAlpha(40)
                : Colors.green.withAlpha(40),
            child: Icon(
              hasAlert ? Icons.warning_amber : Icons.check_circle,
              color: hasAlert ? Colors.orangeAccent : Colors.greenAccent,
            ),
          ),
          title: Text(
            '${t['date']} — ${t['time']}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${t['distance']} km · ${t['duration']} phút · TB ${t['speedAvg']} km/h',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${t['speedMax']}',
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'km/h max',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          onTap: () => _showTripDetail(t),
        ),
      );
    },
  );

  void _showTripDetail(Map<String, dynamic> trip) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '${trip['date']} ${trip['time']}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statCol('${trip['distance']} km', 'Quãng đường'),
                _statCol('${trip['duration']} ph', 'Thời gian'),
                _statCol('${trip['speedAvg']} km/h', 'Tốc độ TB'),
                _statCol('${trip['speedMax']} km/h', 'Tốc độ max'),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '🗺️ Replay tuyến đường (tính năng đang phát triển)',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _statCol(String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.blueAccent,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
    ],
  );

  // ─── ALERTS TAB ────────────────────────────────────
  Widget _buildAlertsTab() => ListView.builder(
    padding: const EdgeInsets.all(12),
    itemCount: _alerts.length,
    itemBuilder: (_, i) {
      final a = _alerts[i];
      final isFall = a['type'] == 'fall';
      return Card(
        color: const Color(0xFF1E293B),
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isFall ? Icons.person_off : Icons.car_crash,
                    color: isFall ? Colors.orangeAccent : Colors.redAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isFall ? '🛑 NGA XE' : '🚨 VA CHẠM',
                    style: TextStyle(
                      color: isFall ? Colors.orangeAccent : Colors.redAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    a['ack'] == true ? Icons.check_circle : Icons.warning,
                    color: a['ack'] == true
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '⚡ Peak G: ${a['peakG']}g · 🧠 AI: ${a['aiP']}% · 📍 ${a['location']}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (isFall)
                Text(
                  '📐 Pitch: ${a['pitch']}°',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  a['date'],
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  // ─── STATS TAB ─────────────────────────────────────
  Widget _buildStatsTab() => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📊 Thống kê tháng 6/2026',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _bigStat('124', 'km'),
            _bigStat('28', 'chuyến'),
            _bigStat('35', 'km/h TB'),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _bigStat('2', 'cảnh báo', color: Colors.orangeAccent),
            _bigStat('0', 'thật', color: Colors.redAccent),
            _bigStat('2', 'false alarm', color: Colors.white38),
          ],
        ),
        const SizedBox(height: 32),
        Container(
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: const Center(
            child: Text(
              '📈 Biểu đồ chuyến đi/ngày\n(tính năng đang phát triển)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _bigStat(
    String value,
    String unit, {
    Color color = Colors.blueAccent,
  }) => Column(
    children: [
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 32,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(unit, style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ],
  );
}
