// lib/home_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'alarm_page.dart';
import 'clock_widgets.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'stopwatch_page.dart';
import 'timer_page.dart';
import 'wavy_nav_bar.dart';

/// App shell with the bottom tab bar: Alarm | Timer | Stopwatch.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _pager = PageController();
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    openTab.addListener(_onOpenTab);
    // Opened by tapping the timer / stopwatch notification?
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final t = await const MethodChannel('com.example.ak47clk/alarm').invokeMethod<int>('takeOpenTab');
        if (t != null && t >= 0) _goTo(t);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    openTab.removeListener(_onOpenTab);
    _pager.dispose();
    super.dispose();
  }

  /// Tab i is (partly) on screen: the current one, or one sliding in during a swipe.
  bool _visible(int i) {
    final p = _pager.hasClients && _pager.position.haveDimensions ? _pager.page : null;
    if (p == null) return _tab == i;
    return (p - i).abs() < 1;
  }

  void _onOpenTab() {
    if (openTab.value >= 0) _goTo(openTab.value);
  }

  void _goTo(int i) {
    if (!mounted || i < 0 || i > 3 || alarmSelecting.value) return;
    Navigator.of(context).popUntil((r) => r.isFirst); // close Settings if it's open
    setState(() => _tab = i);
    if (_pager.hasClients) _pager.jumpToPage(i);
  }

  @override
  Widget build(BuildContext context) {
    // While alarms are being selected: no tab bar, no gear, no swiping.
    return ValueListenableBuilder<bool>(
      valueListenable: alarmSelecting,
      builder: (context, selecting, _) => _scaffold(selecting),
    );
  }

  Widget _scaffold(bool selecting) {
    return Scaffold(
      // Swipe left/right between tabs. _KeepAlive = tabs don't reload when you come back.
      body: Stack(
        children: [
          PageView(
            controller: _pager,
            physics: selecting ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (i) {
              if (!_jumping) setState(() => _tab = i);
            },
            // TickerMode: hidden tabs stop animating (saves CPU/battery). State is timestamp-based,
            // so counting continues; the tab catches up the moment it's shown again.
            children: [
              for (final (i, page) in const [AlarmPage(), TimerPage(), StopwatchPage(), StatsPage()].indexed)
                _KeepAlive(
                  child: AnimatedBuilder(
                    animation: _pager,
                    child: page,
                    builder: (_, child) => TickerMode(enabled: _visible(i), child: child!),
                  ),
                ),
            ],
          ),
          // Settings gear stays fixed while tabs slide underneath.
          if (!selecting) SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      // Wave follows the pager, so it glides on tap and tracks the finger on swipe.
      bottomNavigationBar: selecting ? null : AnimatedBuilder(
        animation: _pager,
        builder: (context, _) => WavyNavBar(
          position: _pager.hasClients && _pager.position.haveDimensions
              ? (_pager.page ?? _tab.toDouble())
              : _tab.toDouble(),
          onTap: _select,
          labels: const ['Alarm', 'Timer', 'Stopwatch', 'Stats'],
          icons: const [Icons.alarm_outlined, Icons.hourglass_empty_rounded, Icons.timer_outlined, Icons.insights_outlined],
          selectedIcons: const [Icons.alarm, Icons.hourglass_full_rounded, Icons.timer, Icons.insights],
        ),
      ),
    );
  }

  Future<void> _select(int i) async {
    setState(() => _tab = i);
    _jumping = true; // keep _tab on the target while the pager slides through middle tabs
    await _pager.animateToPage(i,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    _jumping = false;
  }
}

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

