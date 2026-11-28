// lib/stopwatch_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'clock_widgets.dart';

/// Stopwatch. State is timestamps stored natively, so it keeps counting with the app closed
/// and can be controlled from its notification.
class StopwatchPage extends StatefulWidget {
  const StopwatchPage({super.key});

  @override
  State<StopwatchPage> createState() => _StopwatchPageState();
}

class _StopwatchPageState extends State<StopwatchPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _ch = MethodChannel('com.example.ak47clk/alarm');
  bool _running = false;
  int _startedAt = 0; // epoch ms of last Start
  int _acc = 0; // ms banked before the last Start
  List<int> _laps = []; // cumulative ms at each lap

  late final Ticker _ticker = createTicker((_) => _elapsed.value = _now());
  final ValueNotifier<int> _elapsed = ValueNotifier(0);

  int _now() => _acc + (_running ? DateTime.now().millisecondsSinceEpoch - _startedAt : 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    clockChanged.addListener(_load); // pause / lap / reset from the notification
  }

  @override
  void dispose() {
    clockChanged.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  /// State lives natively (so notification buttons work with the app closed).
  Future<void> _load() async {
    try {
      final raw = await _ch.invokeMethod<String>('getStopwatch') ?? '{}';
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['init'] != true) {
        await _migrateOld(); // first run after update: move old Dart-side state over
        return;
      }
      if (!mounted) return;
      setState(() {
        _running = j['running'] == true;
        _startedAt = (j['start'] as num?)?.toInt() ?? 0;
        _acc = (j['acc'] as num?)?.toInt() ?? 0;
        _laps = [for (final e in (j['laps'] as List? ?? [])) (e as num).toInt()];
      });
      _elapsed.value = _now();
      if (_running && !_ticker.isActive) _ticker.start();
      if (!_running && _ticker.isActive) _ticker.stop();
    } catch (e) {
      debugPrint('getStopwatch failed: $e');
    }
  }

  Future<void> _migrateOld() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _running = p.getBool('sw_running') ?? false;
      _startedAt = p.getInt('sw_start') ?? 0;
      _acc = p.getInt('sw_acc') ?? 0;
      _laps = (p.getStringList('sw_laps') ?? []).map(int.parse).toList();
    });
    await _save();
    for (final k in ['sw_running', 'sw_start', 'sw_acc', 'sw_laps']) {
      await p.remove(k);
    }
    _elapsed.value = _now();
    if (_running && !_ticker.isActive) _ticker.start();
  }

  /// Push state to native (also updates the notification).
  Future<void> _save() async {
    try {
      await _ch.invokeMethod('setStopwatch',
          {'running': _running, 'start': _startedAt, 'acc': _acc, 'laps': _laps});
    } catch (e) {
      debugPrint('setStopwatch failed: $e');
    }
  }

  void _startPause() {
    setState(() {
      if (_running) {
        _acc = _now();
        _running = false;
        _ticker.stop();
      } else {
        _startedAt = DateTime.now().millisecondsSinceEpoch;
        _running = true;
        _ticker.start();
      }
    });
    _elapsed.value = _now();
    _save();
  }

  void _lapOrReset() {
    setState(() {
      if (_running) {
        _laps.add(_now());
      } else {
        _acc = 0;
        _laps = [];
      }
    });
    _elapsed.value = _now();
    _save();
  }

  static String fmt(int ms, {bool centis = true}) {
    final h = ms ~/ 3600000, m = (ms ~/ 60000) % 60, s = (ms ~/ 1000) % 60, cs = (ms ~/ 10) % 100;
    String two(int n) => n.toString().padLeft(2, '0');
    final base = h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
    return centis ? '$base.${two(cs)}' : base;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentOf(context);
    final dim = isDark ? Colors.white54 : Colors.black54;
    final softBg = isDark ? const Color(0xFF1E1F23) : const Color(0xFFF3F4F7);
    final idle = !_running && _acc == 0;

    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 56), // room for the fixed settings gear
          Expanded(
            flex: 5,
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _elapsed,
                      builder: (context, ms, _) => CustomPaint(
                        painter: WatchDialPainter(
                          litColor: accent,
                          isDark: isDark,
                          dots: [
                            // minutes: once an hour, in the gap between face and ticks
                            DialDot(turn: (ms % 3600000) / 3600000, radius: 0.775,
                                size: 0.030, color: hueShift(accent, 150)),
                            // fast: once a second, on the face rim
                            DialDot(turn: (ms % 1000) / 1000, radius: 0.70,
                                size: 0.020, color: hueShift(accent, 210)),
                            // seconds: once a minute, on the tick ring
                            DialDot(turn: (ms % 60000) / 60000, radius: WatchDialPainter.tickRing,
                                size: 0.042, color: accent),
                          ],
                        ),
                        child: Center(
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 56),
                              child: Text(fmt(ms), style: bigDigits(context, 56)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(flex: 4, child: _lapList(dim)),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RoundButton(
                  size: 64,
                  bg: softBg,
                  onTap: idle ? null : _lapOrReset,
                  child: Icon(_running ? Icons.flag_outlined : Icons.refresh_rounded,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
                RoundButton(
                  size: 80,
                  bg: accent,
                  onTap: _startPause,
                  child: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 40, color: isDark ? Colors.black : Colors.white),
                ),
                const SizedBox(width: 64), // keeps the main button centered
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lapList(Color dim) {
    if (_laps.isEmpty) return const SizedBox.shrink();
    final splits = [for (var i = 0; i < _laps.length; i++) _laps[i] - (i == 0 ? 0 : _laps[i - 1])];
    int? fast, slow;
    if (splits.length >= 2) {
      fast = splits.reduce((a, b) => a < b ? a : b);
      slow = splits.reduce((a, b) => a > b ? a : b);
    }
    const green = Color(0xFF34A853), red = Color(0xFFE5534B);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      itemCount: splits.length,
      itemBuilder: (context, j) {
        final i = splits.length - 1 - j; // newest on top
        final split = splits[i];
        final color = split == fast ? green : (split == slow ? red : null);
        final style = TextStyle(
          fontSize: 16,
          color: color ?? Theme.of(context).colorScheme.onSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text('Lap ${i + 1}', style: style.copyWith(color: color ?? dim)),
                    if (color != null)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(split == fast ? 'Fastest' : 'Slowest',
                            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              Text(fmt(split), style: style),
              const SizedBox(width: 24),
              Text(fmt(_laps[i]), style: style.copyWith(color: dim)),
            ],
          ),
        );
      },
    );
  }
}
