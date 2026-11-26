// lib/clock_widgets.dart
// Small shared pieces for the Timer / Stopwatch tabs.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Color accentOf(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF8AB4F8)
    : const Color(0xFF3B6FD8);

/// Big thin digits that don't jitter while counting (tabular figures).
TextStyle bigDigits(BuildContext context, double size) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w200,
      color: Theme.of(context).colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Round button with a squishy press + light haptic.
class RoundButton extends StatefulWidget {
  final double size;
  final Color bg;
  final Widget child;
  final VoidCallback? onTap;
  const RoundButton({super.key, required this.size, required this.bg, required this.child, this.onTap});

  @override
  State<RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<RoundButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.4,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(color: widget.bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Thin ring: track + progress arc (0..1) from 12 o'clock, optional dot at the arc's end.
class RingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color color;
  final bool dotOnly; // stopwatch: just a sweeping dot
  RingPainter({required this.progress, required this.track, required this.color, this.dotOnly = false});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);
    final angle = 2 * math.pi * progress.clamp(0.0, 1.0);
    if (!dotOnly && progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, angle, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color);
    }
    final dot = c + Offset(math.cos(angle - math.pi / 2), math.sin(angle - math.pi / 2)) * r;
    canvas.drawCircle(dot, stroke * 1.1, Paint()..color = color);
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
