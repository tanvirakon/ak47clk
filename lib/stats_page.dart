// lib/stats_page.dart
// Stats tab: today's score, level, streak, charts and badges, built from the native ring log.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'clock_widgets.dart';
import 'stats/stats_engine.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with WidgetsBindingObserver {
  static const _ch = MethodChannel('com.example.ak47clk/alarm');
  Stats? _stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    statsChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    statsChanged.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final since = DateTime.now().subtract(const Duration(days: 400)).millisecondsSinceEpoch;
      final raw = await _ch.invokeMethod<String>('getRingLog', {'since': since});
      final s = Stats.fromEvents(RingEvent.listFromJson(raw ?? '[]'));
      if (mounted) setState(() => _stats = s);
    } catch (_) {
      if (mounted) setState(() => _stats = Stats.fromEvents(const []));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return SafeArea(
      child: s == null
          ? const SizedBox()
          : s.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
                    children: [
                      Text('Stats', style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w300)),
                      const SizedBox(height: 16),
                      _hero(s),
                      const SizedBox(height: 14),
                      _totals(s),
                      _section('This week', 'Rings per day', _weekChart(s)),
                      _section('Wake-up time', 'When you turned the alarm off · 14 days', _wakeChart(s)),
                      _section('Last 10 weeks', 'Brighter = better morning', _heatmap(s)),
                      _section('Badges', '${s.badges.where((b) => b.unlocked).length} of ${s.badges.length} unlocked',
                          _badges(s)),
                    ],
                  ),
                ),
    );
  }

  // ---------------- pieces ----------------

  Color get _soft => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1E1F23)
      : const Color(0xFFF3F4F7);
  Color get _dim => Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54;
  Color get _snoozeColor => hueShift(accentOf(context), 150);
  Color get _extraColor => hueShift(accentOf(context), 210);

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SleepyClock(),
            const SizedBox(height: 20),
            Text('No mornings yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Your first alarm will start your stats', style: TextStyle(color: _dim)),
          ],
        ),
      );

  Widget _hero(Stats s) {
    final accent = accentOf(context);
    final today = s.day(DateTime.now());
    final fg = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today', style: TextStyle(color: _dim, fontSize: 13)),
                    Text(today == null ? '—' : '${today.score}',
                        style: bigDigits(context, 52).copyWith(height: 1.1)),
                    Text(today == null ? 'no alarm yet' : 'points', style: TextStyle(color: _dim, fontSize: 13)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('🔥 ${s.streak}', style: TextStyle(fontSize: 28, color: fg, fontWeight: FontWeight.w300)),
                  Text(s.streak == 1 ? 'day streak' : 'days streak', style: TextStyle(color: _dim, fontSize: 13)),
                  if (s.bestStreak > s.streak)
                    Text('best ${s.bestStreak}', style: TextStyle(color: _dim, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Level ${s.level}', style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${s.totalXp} / ${s.xpForLevel(s.level + 1)} XP', style: TextStyle(color: _dim, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: s.levelProgress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Last-30-day totals.
  Widget _totals(Stats s) {
    final days = s.lastDays(30).map((e) => e.$2).whereType<DayStats>();
    int sum(int Function(DayStats) f) => days.fold(0, (a, d) => a + f(d));
    Widget tile(String n, String label, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Text(n, style: TextStyle(fontSize: 22, color: c, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: _dim, fontSize: 12)),
            ]),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          tile('${sum((d) => d.rings)}', 'rings', accentOf(context)),
          const SizedBox(width: 10),
          tile('${sum((d) => d.snoozes)}', 'snoozes', _snoozeColor),
          const SizedBox(width: 10),
          tile('${sum((d) => d.sleptThrough)}', 'slept through', _extraColor),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text('Last 30 days', style: TextStyle(color: _dim, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _section(String title, String sub, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(sub, style: TextStyle(color: _dim, fontSize: 12)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _legend(List<(Color, String)> items) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 14,
          children: [
            for (final (c, t) in items)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(t, style: TextStyle(color: _dim, fontSize: 12)),
              ]),
          ],
        ),
      );

  Widget _weekChart(Stats s) {
    final week = s.lastDays(7);
    final bars = [
      for (final (_, d) in week)
        _Bar(d?.rings ?? 0, d?.snoozes ?? 0, d?.extraRings ?? 0),
    ];
    return Column(
      children: [
        LayoutBuilder(builder: (context, box) {
          return GestureDetector(
            onTapUp: (e) {
              final i = (e.localPosition.dx / (box.maxWidth / 7)).floor().clamp(0, 6);
              _daySheet(week[i].$1, week[i].$2);
            },
            child: SizedBox(
              height: 150,
              width: box.maxWidth,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, t, __) => CustomPaint(
                  painter: _BarsPainter(
                    bars: bars,
                    labels: [for (final (d, _) in week) DateFormat('E').format(d).substring(0, 1)],
                    grow: t,
                    ring: accentOf(context),
                    snooze: _snoozeColor,
                    extra: _extraColor,
                    track: _soft,
                    text: _dim,
                  ),
                ),
              ),
            ),
          );
        }),
        _legend([(accentOf(context), 'rings'), (_snoozeColor, 'snoozes'), (_extraColor, 'slept through')]),
      ],
    );
  }

  Widget _wakeChart(Stats s) {
    final days = s.lastDays(14);
    final mins = [
      for (final (_, d) in days)
        d?.wokeAt == null ? null : d!.wokeAt!.hour * 60 + d.wokeAt!.minute,
    ];
    if (mins.every((m) => m == null)) {
      return Text('Turn off an alarm to see this chart', style: TextStyle(color: _dim));
    }
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(
        painter: _WakePainter(mins: mins, color: accentOf(context), grid: _soft, text: _dim),
      ),
    );
  }

  Widget _heatmap(Stats s) {
    const weeks = 10;
    final today = Stats.dayOf(DateTime.now());
    // Columns = weeks (Mon first row), last column = this week.
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final start = DateTime(monday.year, monday.month, monday.day - 7 * (weeks - 1));
    final accent = accentOf(context);
    return LayoutBuilder(builder: (context, box) {
      const gap = 4.0;
      final cell = math.min(22.0, (box.maxWidth - gap * (weeks - 1)) / weeks);
      return Row(
        children: [
          for (var w = 0; w < weeks; w++)
            Padding(
              padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
              child: Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    () {
                      final day = DateTime(start.year, start.month, start.day + w * 7 + d);
                      final st = s.day(day);
                      final future = day.isAfter(today);
                      final c = future
                          ? Colors.transparent
                          : st == null
                              ? _soft
                              : Color.lerp(accent.withValues(alpha: 0.18), accent,
                                  (st.score / (kCleanWake + kFastBonus)).clamp(0.0, 1.0))!;
                      return GestureDetector(
                        onTap: future ? null : () => _daySheet(day, st),
                        child: Container(
                          width: cell,
                          height: cell,
                          margin: const EdgeInsets.only(bottom: gap),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(5),
                            border: day == today ? Border.all(color: accent, width: 1.5) : null,
                          ),
                        ),
                      );
                    }(),
                ],
              ),
            ),
        ],
      );
    });
  }

  static const _badgeIcons = {
    'first_ring': Icons.alarm_on_rounded,
    'lightning': Icons.bolt_rounded,
    'early_bird': Icons.wb_twilight_rounded,
    'comeback': Icons.replay_rounded,
    'week': Icons.local_fire_department_rounded,
    'iron': Icons.shield_rounded,
  };

  Widget _badges(Stats s) {
    final accent = accentOf(context);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.9,
      children: [
        for (final b in s.badges)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text('${b.title}: ${b.hint}${b.unlocked ? ' ✓' : ''}')));
            },
            child: Container(
              decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(18)),
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: b.unlocked ? accent : _dim.withValues(alpha: 0.12),
                      boxShadow: b.unlocked
                          ? [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 12)]
                          : null,
                    ),
                    child: Icon(b.unlocked ? _badgeIcons[b.id] : Icons.lock_outline_rounded,
                        color: b.unlocked ? Theme.of(context).colorScheme.onPrimary : _dim, size: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(b.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(fontSize: 12, color: b.unlocked ? null : _dim)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _daySheet(DateTime day, DayStats? d) {
    HapticFeedback.selectionClick();
    final t = DateFormat('h:mm a');
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(DateFormat('EEEE, d MMMM').format(day), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(d == null ? 'No alarms rang' : '${d.score} points${d.clean ? ' · clean morning ✨' : ''}',
                  style: TextStyle(color: _dim)),
              const SizedBox(height: 12),
              if (d != null)
                for (final s in d.sessions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(s.clean ? Icons.check_circle_rounded : Icons.bedtime_rounded,
                        color: s.clean ? accentOf(context) : _snoozeColor),
                    title: Text('${t.format(s.start)} · ${s.single ? 'alarm' : 'series'}'),
                    subtitle: Text([
                      'rang ${s.rings}×',
                      if (s.snoozes > 0) 'snoozed ${s.snoozes}×',
                      if (s.extraRings > 0) 'slept through ${s.extraRings}',
                      if (s.wokeAt != null) 'up at ${t.format(s.wokeAt!)}',
                    ].join(' · ')),
                    trailing: Text('+${s.score}', style: TextStyle(color: accentOf(context))),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- painters ----------------

class _Bar {
  final int rings, snoozes, extra;
  const _Bar(this.rings, this.snoozes, this.extra);
}

/// Rounded bars per day: snoozes and slept-through rings stacked on top of normal rings.
class _BarsPainter extends CustomPainter {
  final List<_Bar> bars;
  final List<String> labels;
  final double grow;
  final Color ring, snooze, extra, track, text;
  _BarsPainter({
    required this.bars,
    required this.labels,
    required this.grow,
    required this.ring,
    required this.snooze,
    required this.extra,
    required this.track,
    required this.text,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 20.0;
    final h = size.height - labelH;
    final slot = size.width / bars.length;
    final w = math.min(22.0, slot * 0.5);
    final maxV = math.max(4, bars.fold<int>(0, (m, b) => math.max(m, b.rings)));
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final x = slot * i + (slot - w) / 2;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, w, h), Radius.circular(w / 2)), Paint()..color = track);
      if (b.rings > 0) {
        final total = h * (b.rings / maxV) * grow;
        // Segments bottom-up: normal rings, snooze rings, slept-through rings.
        final snz = math.min(b.snoozes, b.rings), ext = math.min(b.extra, b.rings - snz);
        final normal = b.rings - snz - ext;
        canvas.save();
        canvas.clipRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, h - total, w, total), Radius.circular(w / 2)));
        var y = h;
        for (final (n, c) in [(normal, ring), (snz, snooze), (ext, extra)]) {
          final seg = total * n / b.rings;
          canvas.drawRect(Rect.fromLTWH(x, y - seg, w, seg), Paint()..color = c);
          y -= seg;
        }
        canvas.restore();
      }
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: TextStyle(color: text, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(slot * i + (slot - tp.width) / 2, h + 4));
    }
  }

  @override
  bool shouldRepaint(_BarsPainter o) =>
      o.grow != grow || o.ring != ring || o.track != track || o.bars != bars;
}

/// Wake-up time per day: soft line + glowing dots, earliest on top.
class _WakePainter extends CustomPainter {
  final List<int?> mins;
  final Color color, grid, text;
  _WakePainter({required this.mins, required this.color, required this.grid, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    const labelW = 52.0;
    final vals = mins.whereType<int>();
    var lo = vals.reduce(math.min) - 15, hi = vals.reduce(math.max) + 15;
    if (hi - lo < 60) {
      final mid = (hi + lo) ~/ 2;
      lo = mid - 30;
      hi = mid + 30;
    }
    final w = size.width - labelW;
    double yOf(int m) => (m - lo) / (hi - lo) * size.height;
    double xOf(int i) => labelW + w * (i + 0.5) / mins.length;

    String fmt(int m) {
      final mm = ((m % 1440) + 1440) % 1440;
      return DateFormat('h:mm a').format(DateTime(2000, 1, 1, mm ~/ 60, mm % 60));
    }

    for (final m in [lo, (lo + hi) ~/ 2, hi]) {
      final y = yOf(m).clamp(6.0, size.height - 6);
      canvas.drawLine(Offset(labelW, y), Offset(size.width, y), Paint()..color = grid..strokeWidth = 1);
      final tp = TextPainter(
        text: TextSpan(text: fmt(m), style: TextStyle(color: text, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    final line = Path();
    var open = false;
    for (var i = 0; i < mins.length; i++) {
      final m = mins[i];
      if (m == null) continue;
      final p = Offset(xOf(i), yOf(m));
      open ? line.lineTo(p.dx, p.dy) : line.moveTo(p.dx, p.dy);
      open = true;
    }
    canvas.drawPath(line, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.45));
    for (var i = 0; i < mins.length; i++) {
      final m = mins[i];
      if (m == null) continue;
      final p = Offset(xOf(i), yOf(m));
      canvas.drawCircle(p, 8, Paint()
        ..color = color.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(p, 4.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_WakePainter o) => o.color != color || o.mins != mins;
}
