// lib/timer_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'clock_widgets.dart';
import 'wheel_time_picker.dart';

/// Countdown timer. Native side owns the state + rings (works locked / app killed / after reboot).
class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const platform = MethodChannel('com.example.ak47clk/alarm');

  int _end = 0; // >0 running: epoch ms when it rings
  int _left = 0; // >0 paused: ms left
  int _total = 0; // full duration for the ring

  // wheel draft (idle view)
  int _h = 0, _m = 5, _s = 0;
  late FixedExtentScrollController _hc, _mc, _sc;

  late final Ticker _ticker = createTicker((_) => _onTick());
  final ValueNotifier<int> _remaining = ValueNotifier(0);

  bool get _isRunning => _end > 0;
  bool get _isPaused => _end == 0 && _left > 0;
  bool get _isIdle => !_isRunning && !_isPaused;
  int get _draftMs => ((_h * 60 + _m) * 60 + _s) * 1000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _makeWheels();
    _load();
    clockChanged.addListener(_load); // paused / +1 / cancelled from the notification
  }

  @override
  void dispose() {
    clockChanged.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _remaining.dispose();
    _hc.dispose();
    _mc.dispose();
    _sc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(); // timer may have rung while away
  }

  /// Fresh controllers each time the wheels are shown (big offset = loops both ways).
  void _makeWheels() {
    _hc = FixedExtentScrollController(initialItem: 2400 + _h);
    _mc = FixedExtentScrollController(initialItem: 6000 + _m);
    _sc = FixedExtentScrollController(initialItem: 6000 + _s);
  }

  void _resetWheels() {
    final old = [_hc, _mc, _sc];
    _makeWheels();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final last = p.getInt('timer_last_ms');
    try {
      final raw = await platform.invokeMethod<String>('getTimer') ?? '{}';
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final end = (j['end'] as num?)?.toInt() ?? 0;
      final left = (j['left'] as num?)?.toInt() ?? 0;
      final total = (j['total'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      final wasIdle = _isIdle;
      setState(() {
        _end = end > DateTime.now().millisecondsSinceEpoch ? end : 0;
        _left = _end == 0 ? left : 0;
        _total = total;
        if (_isIdle && last != null && last > 0 && wasIdle) {
          final sec = last ~/ 1000;
          _h = sec ~/ 3600;
          _m = (sec ~/ 60) % 60;
          _s = sec % 60;
        }
      });
      if (_isIdle) _resetWheels();
      _sync();
    } catch (e) {
      debugPrint('getTimer failed: $e');
    }
  }

  /// Push state to native (schedules / cancels the ring + notification).
  Future<void> _push() async {
    try {
      await platform.invokeMethod('setTimer', {'end': _end, 'left': _left, 'total': _total});
    } catch (e) {
      debugPrint('setTimer failed: $e');
    }
  }

  void _sync() {
    _onTick();
    if (_isRunning && !_ticker.isActive) _ticker.start();
    if (!_isRunning && _ticker.isActive) _ticker.stop();
  }

  void _onTick() {
    if (_isRunning) {
      final r = _end - DateTime.now().millisecondsSinceEpoch;
      if (r <= 0) {
        // Native rings now; just show idle again. (Don't call native: it would cancel the ring.)
        _remaining.value = 0;
        _ticker.stop();
        setState(() {
          _end = 0;
          _left = 0;
        });
        _resetWheels();
        return;
      }
      _remaining.value = r;
    } else {
      _remaining.value = _left;
    }
  }

  Future<void> _start(int ms) async {
    if (ms <= 0) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt('timer_last_ms', ms);
    setState(() {
      _total = ms;
      _left = 0;
      _end = DateTime.now().millisecondsSinceEpoch + ms;
    });
    _sync();
    _push();
  }

  void _pauseResume() {
    setState(() {
      if (_isRunning) {
        _left = _end - DateTime.now().millisecondsSinceEpoch;
        _end = 0;
      } else {
        _end = DateTime.now().millisecondsSinceEpoch + _left;
        _left = 0;
      }
    });
    _sync();
    _push();
  }

  void _addMinute() {
    setState(() {
      if (_isRunning) {
        _end += 60000;
      } else {
        _left += 60000;
      }
      _total += 60000;
    });
    _sync();
    _push();
  }

  void _cancel() {
    setState(() {
      _end = 0;
      _left = 0;
    });
    _resetWheels();
    _sync();
    _push();
  }

  static String fmt(int ms) {
    final sec = (ms + 999) ~/ 1000; // round up: shows 00:01 until it really ends
    final h = sec ~/ 3600, m = (sec ~/ 60) % 60, s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 56), // room for the fixed settings gear
          Expanded(child: _isIdle ? _idleView() : _runningView()),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 20),
            child: _controls(),
          ),
        ],
      ),
    );
  }

  Widget _idleView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? Colors.white38 : Colors.black38;
    final accent = accentOf(context);

    Widget unit(String t) => Padding(
          padding: const EdgeInsets.only(left: 2, right: 6, top: 8),
          child: Text(t, style: TextStyle(color: dim, fontSize: 15)),
        );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 64.0 * 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: DialWheel(
                      controller: _hc, count: 24, value: _h, onChanged: (v) => setState(() => _h = v)),
                ),
                unit('h'),
                Expanded(
                  child: DialWheel(
                      controller: _mc, count: 60, value: _m, onChanged: (v) => setState(() => _m = v)),
                ),
                unit('m'),
                Expanded(
                  child: DialWheel(
                      controller: _sc, count: 60, value: _s, onChanged: (v) => setState(() => _s = v)),
                ),
                unit('s'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        // Quick presets: tap = start right away.
        Wrap(
          spacing: 10,
          children: [1, 5, 10, 15].map((min) {
            return ActionChip(
              label: Text('$min min'),
              shape: const StadiumBorder(),
              side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
              backgroundColor: accent.withValues(alpha: 0.08),
              onPressed: () {
                HapticFeedback.lightImpact();
                final sec = min * 60;
                setState(() {
                  _h = 0;
                  _m = min;
                  _s = 0;
                });
                _start(sec * 1000);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _runningView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentOf(context);
    final dim = isDark ? Colors.white54 : Colors.black54;
    final track = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06);

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: RepaintBoundary(
            child: ValueListenableBuilder<int>(
              valueListenable: _remaining,
              builder: (context, ms, _) => CustomPaint(
                painter: RingPainter(
                  progress: _total > 0 ? ms / _total : 0, // drains as time passes
                  track: track,
                  color: _isPaused ? dim : accent,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(fmt(ms), style: bigDigits(context, 60)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isPaused
                            ? 'Paused'
                            : 'Ends ${DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(_end))}',
                        style: TextStyle(color: dim, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentOf(context);
    final fg = Theme.of(context).colorScheme.onSurface;
    final softBg = isDark ? const Color(0xFF1E1F23) : const Color(0xFFF3F4F7);
    final onAccent = isDark ? Colors.black : Colors.white;

    if (_isIdle) {
      return Center(
        child: RoundButton(
          size: 80,
          bg: accent,
          onTap: _draftMs > 0 ? () => _start(_draftMs) : null,
          child: Icon(Icons.play_arrow_rounded, size: 40, color: onAccent),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RoundButton(size: 64, bg: softBg, onTap: _cancel, child: Icon(Icons.close_rounded, color: fg)),
        RoundButton(
          size: 80,
          bg: accent,
          onTap: _pauseResume,
          child: Icon(_isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 40, color: onAccent),
        ),
        RoundButton(
          size: 64,
          bg: softBg,
          onTap: _addMinute,
          child: Text('+1:00', style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
