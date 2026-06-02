import 'package:flutter/material.dart';

/// Settings Screen — Cài đặt app
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _emergencyPhone1 = '0868314386';
  String _emergencyPhone2 = '';
  String _gpsMode = 'Auto'; // Auto / NEO-6M / Phone
  String _language = 'Tiếng Việt';
  bool _darkMode = true;
  bool _vibration = true;
  int _autoCallSec = 15;
  int _autoSosSec = 30;
  double _volumeAlarm = 0.8;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('⚙️ Cài đặt'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── EMERGENCY CONTACTS ───
          _sectionHeader('📞 Liên hệ khẩn cấp'),
          _buildTextField(
            'Người thân 1',
            _emergencyPhone1,
            (v) => _emergencyPhone1 = v,
            Icons.person,
          ),
          _buildTextField(
            'Người thân 2',
            _emergencyPhone2,
            (v) => _emergencyPhone2 = v,
            Icons.person_add,
          ),
          const SizedBox(height: 16),

          // ─── ALERT SETTINGS ───
          _sectionHeader('🚨 Cảnh báo'),
          _buildDropdown('Tự động gọi', _autoCallSec, [
            10,
            15,
            20,
            30,
          ], (v) => setState(() => _autoCallSec = v)),
          _buildDropdown('Tự động SOS', _autoSosSec, [
            15,
            30,
            45,
            60,
          ], (v) => setState(() => _autoSosSec = v)),
          SwitchListTile(
            title: const Text(
              'Rung khi cảnh báo',
              style: TextStyle(color: Colors.white),
            ),
            value: _vibration,
            activeColor: Colors.green,
            onChanged: (v) => setState(() => _vibration = v),
          ),
          ListTile(
            title: const Text(
              'Âm lượng cảnh báo',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Slider(
              value: _volumeAlarm,
              min: 0,
              max: 1,
              divisions: 10,
              activeColor: Colors.orange,
              label: '${(_volumeAlarm * 100).toInt()}%',
              onChanged: (v) => setState(() => _volumeAlarm = v),
            ),
          ),
          const SizedBox(height: 16),

          // ─── GPS ───
          _sectionHeader('🛰️ GPS'),
          _buildChoiceChips('Nguồn GPS', _gpsMode, [
            'Auto',
            'NEO-6M',
            'Phone',
          ], (v) => setState(() => _gpsMode = v)),
          const SizedBox(height: 16),

          // ─── APPEARANCE ───
          _sectionHeader('🎨 Giao diện'),
          SwitchListTile(
            title: const Text(
              'Dark Mode',
              style: TextStyle(color: Colors.white),
            ),
            value: _darkMode,
            activeColor: Colors.blue,
            onChanged: (v) => setState(() => _darkMode = v),
          ),
          ListTile(
            title: const Text(
              'Ngôn ngữ',
              style: TextStyle(color: Colors.white),
            ),
            trailing: Text(
              _language,
              style: const TextStyle(color: Colors.white54),
            ),
            onTap: () => setState(
              () => _language = _language == 'Tiếng Việt'
                  ? 'English'
                  : 'Tiếng Việt',
            ),
          ),
          const SizedBox(height: 16),

          // ─── ABOUT ───
          _sectionHeader('ℹ️ Về ứng dụng'),
          const ListTile(
            title: Text('Phiên bản', style: TextStyle(color: Colors.white)),
            trailing: Text('1.0.0', style: TextStyle(color: Colors.white54)),
          ),
          const ListTile(
            title: Text('Tác giả', style: TextStyle(color: Colors.white)),
            trailing: Text(
              'Đào Văn Phong - PTIT 2026',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        color: Colors.blueAccent,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _buildTextField(
    String label,
    String value,
    Function(String) onChanged,
    IconData icon,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: TextEditingController(text: value),
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.white54),
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      keyboardType: TextInputType.phone,
    ),
  );

  Widget _buildDropdown(
    String label,
    int value,
    List<int> items,
    Function(int) onChanged,
  ) => ListTile(
    title: Text(label, style: const TextStyle(color: Colors.white)),
    trailing: DropdownButton<int>(
      value: value,
      dropdownColor: const Color(0xFF1E293B),
      style: const TextStyle(color: Colors.white),
      items: items
          .map((i) => DropdownMenuItem(value: i, child: Text('$i giây')))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );

  Widget _buildChoiceChips(
    String label,
    String selected,
    List<String> options,
    Function(String) onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        Wrap(
          spacing: 8,
          children: options
              .map(
                (o) => ChoiceChip(
                  label: Text(
                    o,
                    style: TextStyle(
                      color: selected == o ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selected: selected == o,
                  selectedColor: Colors.blueAccent,
                  backgroundColor: const Color(0xFF1E293B),
                  onSelected: (_) => onChanged(o),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}
