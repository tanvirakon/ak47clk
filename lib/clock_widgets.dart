// lib/clock_widgets.dart
// Small shared pieces for the Timer / Stopwatch tabs.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native -> Flutter events from the timer / stopwatch notifications.
/// clockChanged bumps when a notification button changed state; openTab = tab to show.
final ValueNotifier<int> clockChanged = ValueNotifier(0);
final ValueNotifier<int> openTab = ValueNotifier(-1);

void initClockEvents() {
  const MethodChannel('com.example.ak47clk/alarm').setMethodCallHandler((call) async {
    switch (call.method) {
      case 'clockChanged':
        clockChanged.value++;
      case 'openTab':
        openTab.value = -1; // re-fire even if it's the same tab
        openTab.value = (call.arguments as num).toInt();
    }
    return null;
  });
}

/// App accent (chosen in Settings).
Color accentOf(BuildContext context) => Theme.of(context).colorScheme.primary;

/// Switch with a little bounce + haptic when flipped.
class BouncySwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const BouncySwitch({super.key, required this.value, required this.onChanged});

  @override
  State<BouncySwitch> createState() => _BouncySwitchState();
}

class _BouncySwitchState extends State<BouncySwitch> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.14).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.14, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 65),
  ]).animate(_c);

  @override
  void didUpdateWidget(BouncySwitch old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _c.forward(from: 0); // bounce on any change, incl. from outside
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Switch(
        value: widget.value,
        onChanged: widget.onChanged == null
            ? null
            : (v) {
                HapticFeedback.lightImpact();
                widget.onChanged!(v);
              },
      ),
    );
  }
}

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

/// Empty-list art: a sleepy alarm clock gently floating, with "z"s drifting up.
class SleepyClock extends StatefulWidget {
  final double size;
  const SleepyClock({super.key, this.size = 150});

  @override
  State<SleepyClock> createState() => _SleepyClockState();
}

class _SleepyClockState extends State<SleepyClock> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _SleepyClockPainter(
              t: _c.value,
              accent: accentOf(context),
              face: isDark ? const Color(0xFF1E1F23) : const Color(0xFFF3F4F7),
              ink: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
        ),
      ),
    );
  }
}

class _SleepyClockPainter extends CustomPainter {
  final double t; // 0..1 loop
  final Color accent, face, ink;
  _SleepyClockPainter({required this.t, required this.accent, required this.face, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final bob = math.sin(t * 2 * math.pi) * s * 0.025; // gentle float
    final c = Offset(s * 0.5, s * 0.58 + bob); // centered; z's float in the top-right corner
    final r = s * 0.27;

    // soft glow
    canvas.drawCircle(c, r * 1.35, Paint()..color = accent.withValues(alpha: 0.10));

    // bells
    final bell = Paint()..color = accent;
    for (final side in [-1, 1]) {
      final bc = c + Offset(side * r * 0.62, -r * 0.88);
      canvas.drawArc(Rect.fromCircle(center: bc, radius: r * 0.34), math.pi, math.pi, true, bell);
    }
    // legs
    final leg = Paint()
      ..color = accent
      ..strokeWidth = s * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + Offset(-r * 0.55, r * 0.8), c + Offset(-r * 0.8, r * 1.12), leg);
    canvas.drawLine(c + Offset(r * 0.55, r * 0.8), c + Offset(r * 0.8, r * 1.12), leg);

    // face + rim
    canvas.drawCircle(c, r, Paint()..color = face);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..color = accent);

    // sleepy closed eyes (little arcs) + hands
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.02
      ..strokeCap = StrokeCap.round
      ..color = ink;
    for (final side in [-1, 1]) {
      canvas.drawArc(Rect.fromCircle(center: c + Offset(side * r * 0.36, -r * 0.12), radius: r * 0.14),
          0.2, math.pi - 0.4, false, line);
    }
    canvas.drawArc(Rect.fromCircle(center: c + Offset(0, r * 0.3), radius: r * 0.12), 0.3, math.pi - 0.6, false, line);

    // three z's drifting up-right, staggered
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final opacity = math.sin(p * math.pi); // fade in, then out
      final pos = Offset(s * 0.70 + p * s * 0.14, s * 0.34 - p * s * 0.30);
      final tp = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            fontSize: s * (0.10 + 0.06 * p),
            fontWeight: FontWeight.w600,
            color: accent.withValues(alpha: 0.85 * opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos);
    }
  }

  @override
  bool shouldRepaint(_SleepyClockPainter old) =>
      old.t != t || old.accent != accent || old.face != face || old.ink != ink;
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
