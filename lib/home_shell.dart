// lib/home_shell.dart
import 'package:flutter/material.dart';
import 'alarm_page.dart';
import 'settings_page.dart';

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
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Swipe left/right between tabs. _KeepAlive = tabs don't reload when you come back.
      body: Stack(
        children: [
          PageView(
            controller: _pager,
            onPageChanged: (i) {
              if (!_jumping) setState(() => _tab = i);
            },
            children: const [
              _KeepAlive(child: AlarmPage()),
              _KeepAlive(child: _ComingSoon(icon: Icons.hourglass_empty_rounded)),
              _KeepAlive(child: _ComingSoon(icon: Icons.timer_outlined)),
            ],
          ),
          // Settings gear stays fixed while tabs slide underneath.
          SafeArea(
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) async {
          setState(() => _tab = i);
          _jumping = true; // don't flicker the bar through middle tabs (Alarm -> Stopwatch)
          await _pager.animateToPage(i,
              duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
          _jumping = false;
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide, // icons only
        height: 60,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.alarm_outlined), selectedIcon: Icon(Icons.alarm), label: 'Alarm'),
          NavigationDestination(
              icon: Icon(Icons.hourglass_empty_rounded),
              selectedIcon: Icon(Icons.hourglass_full_rounded),
              label: 'Timer'),
          NavigationDestination(
              icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: 'Stopwatch'),
        ],
      ),
    );
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

class _ComingSoon extends StatelessWidget {
  final IconData icon;
  const _ComingSoon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).brightness == Brightness.dark ? Colors.white38 : Colors.black38;
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: dim),
            const SizedBox(height: 12),
            Text('Coming soon', style: TextStyle(color: dim, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
