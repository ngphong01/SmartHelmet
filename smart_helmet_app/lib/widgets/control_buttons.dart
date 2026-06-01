import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ControlButtons extends StatelessWidget {
  final VoidCallback onAck;
  final VoidCallback onSos;
  final VoidCallback onTestImpact;
  const ControlButtons({
    super.key,
    required this.onAck,
    required this.onSos,
    required this.onTestImpact,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StaticButton(
                label: 'TÔI ỔN',
                icon: Icons.check_circle_rounded,
                gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                glowColor: const Color(0xFF10B981),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onAck();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PulseButton(
                label: 'SOS',
                icon: Icons.warning_rounded,
                gradient: const [Color(0xFFEF4444), Color(0xFFDC2626)],
                glowColor: const Color(0xFFEF4444),
                pulse: true,
                onTap: () {
                  HapticFeedback.heavyImpact();
                  onSos();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _StaticButton(
            label: '🧪 TEST VA CHẠM',
            icon: Icons.science_rounded,
            gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
            glowColor: const Color(0xFFF59E0B),
            onTap: () {
              HapticFeedback.heavyImpact();
              onTestImpact();
            },
          ),
        ),
      ],
    );
  }
}

class _StaticButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color glowColor;
  final VoidCallback onTap;

  const _StaticButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.glowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: glowColor.withAlpha(80), width: 1.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradient[0].withAlpha(30), gradient[1].withAlpha(15)],
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withAlpha(50),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: gradient[0], size: 34),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: gradient[0],
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color glowColor;
  final VoidCallback onTap;
  final bool pulse;

  const _PulseButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.glowColor,
    required this.onTap,
    this.pulse = false,
  });

  @override
  State<_PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<_PulseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final shadow = widget.pulse && _ctrl.isAnimating
            ? BoxShadow(
                color: widget.glowColor.withAlpha(
                  (40 + (_ctrl.value * 60)).toInt(),
                ),
                blurRadius: 16 + _ctrl.value * 16,
                spreadRadius: _ctrl.value * 6,
              )
            : BoxShadow(
                color: widget.glowColor.withAlpha(50),
                blurRadius: 14,
                spreadRadius: 2,
              );

        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: widget.glowColor.withAlpha(80),
                width: 1.5,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.gradient[0].withAlpha(30),
                  widget.gradient[1].withAlpha(15),
                ],
              ),
              boxShadow: [shadow],
            ),
            child: Column(
              children: [
                Icon(widget.icon, color: widget.gradient[0], size: 34),
                const SizedBox(height: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.gradient[0],
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
