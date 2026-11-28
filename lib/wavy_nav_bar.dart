// lib/wavy_nav_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'clock_widgets.dart';

/// Bottom bar whose top edge dips under the selected tab, with the selected icon
/// in a floating accent circle. [position] is fractional (pager page) so the
/// wave follows a swipe.
class WavyNavBar extends StatelessWidget {
  final double position;
  final ValueChanged<int> onTap;
  final List<IconData> icons;
  final List<IconData> selectedIcons;
  final List<String> labels;

  const WavyNavBar({
    super.key,
    required this.position,
    required this.onTap,
    required this.icons,
    required this.selectedIcons,
    required this.labels,
  });

  static const double _top = 22; // transparent strip the circle pokes into
  static const double _barH = 60;
  static const double _circle = 52;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = accentOf(context);
    final fg = theme.colorScheme.onSurface;
    final barColor = isDark ? const Color(0xFF1C1D22) : Colors.white;
    final n = icons.length;
    final p = position.clamp(0.0, (n - 1).toDouble());
    final lo = p.floor(), hi = p.ceil();
    final t = p - lo;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: _top + _barH,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final cx = (p + 0.5) * w / n;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _WavePainter(
                    cx: cx,
                    top: _top,
                    color: barColor,
                    shadow: Colors.black.withValues(alpha: isDark ? 0.6 : 0.18),
                  ),
                ),
              ),
              // Flat icons; the one under the circle fades out.
              Positioned(
                left: 0,
                right: 0,
                top: _top,
                height: _barH,
                child: Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == p.round(),
                          label: labels[i],
                          child: InkResponse(
                            radius: 30,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onTap(i);
                            },
                            child: Center(
                              child: Opacity(
                                opacity: (p - i).abs().clamp(0.0, 1.0),
                                child: Icon(icons[i], color: fg.withValues(alpha: 0.55)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Floating circle sitting in the dip.
              Positioned(
                left: cx - _circle / 2,
                top: _top - _circle / 2 + 4,
                width: _circle,
                height: _circle,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: 1 - t,
                          child: Icon(selectedIcons[lo], color: theme.colorScheme.onPrimary),
                        ),
                        if (hi != lo)
                          Opacity(
                            opacity: t,
                            child: Icon(selectedIcons[hi], color: theme.colorScheme.onPrimary),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double cx, top;
  final Color color, shadow;
  _WavePainter({required this.cx, required this.top, required this.color, required this.shadow});

  static const double _half = 62; // half width of the dip incl. shoulders
  static const double _depth = 34;

  @override
  void paint(Canvas canvas, Size size) {
    final b = top + _depth;
    final path = Path()
      ..moveTo(0, top)
      ..lineTo(cx - _half, top)
      ..cubicTo(cx - _half * 0.55, top, cx - _half * 0.62, b, cx, b)
      ..cubicTo(cx + _half * 0.62, b, cx + _half * 0.55, top, cx + _half, top)
      ..lineTo(size.width, top)
      ..lineTo(size.width, size.height + 40) // run under the safe-area inset
      ..lineTo(0, size.height + 40)
      ..close();
    canvas.drawShadow(path, shadow, 8, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.cx != cx || old.top != top || old.color != color || old.shadow != shadow;
}
