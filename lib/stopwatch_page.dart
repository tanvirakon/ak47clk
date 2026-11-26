// lib/stopwatch_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'clock_widgets.dart';

/// Stopwatch. State is timestamps in prefs, so it keeps counting with the app closed.
class StopwatchPage extends StatefulWidget {
  const StopwatchPage({super.key});

  @override
  State<StopwatchPage> createState() => _StopwatchPageState();
}

class _StopwatchPageState extends State<StopwatchPage> with SingleTickerProviderStateMixin {
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
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _running = p.getBool('sw_running') ?? false;
      _startedAt = p.getInt('sw_start') ?? 0;
      _acc = p.getInt('sw_acc') ?? 0;
      _laps = (p.getStringList('sw_laps') ?? []).map(int.parse).toList();
    });
    _elapsed.value = _now();
    if (_running && !_ticker.isActive) _ticker.start();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('sw_running', _running);
    await p.setInt('sw_start', _startedAt);
    await p.setInt('sw_acc', _acc);
    await p.setStringList('sw_laps', _laps.map((e) => '$e').toList());
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
    final track = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06);
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
                        painter: RingPainter(
                          progress: (ms % 60000) / 60000, // dot sweeps once a minute
                          track: track,
                          color: accent,
                          dotOnly: true,
                        ),
                        child: Center(
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
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
              Expanded(child: Text('Lap ${i + 1}', style: style.copyWith(color: color ?? dim))),
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
