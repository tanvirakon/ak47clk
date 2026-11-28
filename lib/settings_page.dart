// lib/settings_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'buttons_page.dart';
import 'clock_widgets.dart';
import 'theme_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const platform = MethodChannel('com.example.ak47clk/alarm');
  String _ringtoneName = '';

  @override
  void initState() {
    super.initState();
    _loadRingtoneName();
    _loadButtons();
  }

  String _buttonsSummary = 'Off';

  Future<void> _loadButtons() async {
    final b = await loadButtons();
    if (mounted) setState(() => _buttonsSummary = buttonsSummary(b));
  }

  Future<void> _loadRingtoneName() async {
    try {
      final name = await platform.invokeMethod<String>('getRingtoneName');
      if (mounted) setState(() => _ringtoneName = name ?? 'Default');
    } catch (_) {
      if (mounted) setState(() => _ringtoneName = 'Default');
    }
  }

  bool _savingVideo = false;

  /// Ask Tone or Video, then open the matching native picker.
  Future<void> _pickRingtone() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _sourceSheet(ctx),
    );
    if (choice == null) return;

    if (choice == 'video') setState(() => _savingVideo = true);
    try {
      final name = await platform.invokeMethod<String>(
        choice == 'video' ? 'pickVideo' : 'pickRingtone',
      );
      if (name != null && mounted) setState(() => _ringtoneName = name);
    } catch (e) {
      // Never fail silently (PlatformException, MissingPluginException, ...)
      final msg = e is PlatformException
          ? (e.message ?? 'Could not set ringtone')
          : 'Could not open picker. Restart the app and try again.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _savingVideo = false);
    }
  }

  Widget _sourceSheet(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final dim = isDark ? Colors.white54 : Colors.black54;
    Widget option(IconData icon, String title, String sub, String value) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontSize: 17)),
          subtitle: Text(sub, style: TextStyle(color: dim, fontSize: 13)),
          onTap: () => Navigator.pop(ctx, value),
        );

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Alarm ringtone', style: TextStyle(color: dim, fontSize: 14)),
              ),
            ),
            option(Icons.music_note_outlined, 'Tone', 'System alarm sounds', 'tone'),
            option(Icons.movie_outlined, 'Video', 'Plays fullscreen with sound', 'video'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);
    final dim = theme.brightness == Brightness.dark
        ? Colors.white54
        : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 8),
          const Text(
            'Settings',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 32),
          _sectionHeader('DISPLAY', dim),
          _row(
            title: 'Dark mode',
            trailing: BouncySwitch(
              value: themeProvider.isDarkMode,
              onChanged: themeProvider.toggleTheme,
            ),
            onTap: () => themeProvider.toggleTheme(!themeProvider.isDarkMode),
          ),
          const SizedBox(height: 4),
          const Text('Accent colour', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 14),
          _accentPicker(themeProvider),
          const SizedBox(height: 16),
          Divider(color: dim.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          _sectionHeader('GENERAL SETTINGS', dim),
          _row(
            title: 'Alarm ringtone',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: _savingVideo
                      ? const Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(
                          _ringtoneName,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: dim, fontSize: 14),
                        ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: dim),
              ],
            ),
            onTap: _pickRingtone,
          ),
          _row(
            title: 'Buttons while ringing',
            subtitle: _buttonsSummary,
            trailing: Icon(Icons.chevron_right, color: dim),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ButtonsPage()));
              _loadButtons();
            },
          ),
          _row(
            title: 'Test alarm',
            subtitle: _testLeft > 0
                ? 'Ringing in $_testLeft s… you may lock your phone.'
                : 'Rings in 10 seconds. You may lock your phone.',
            trailing: _testCountdown(theme.colorScheme.primary),
            onTap: _testLeft > 0 ? () {} : _testAlarm,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Test alarm countdown (seconds left; 0 = idle)
  int _testLeft = 0;
  Timer? _testTimer;

  @override
  void dispose() {
    _testTimer?.cancel();
    super.dispose();
  }

  /// Play icon when idle; while waiting, a draining ring with the seconds left.
  Widget _testCountdown(Color accent) {
    return SizedBox(
      width: 32,
      height: 32,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _testLeft > 0
            ? Stack(
                key: const ValueKey('count'),
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: _testLeft / 10),
                    duration: const Duration(milliseconds: 900),
                    builder: (_, v, __) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 2.5,
                      color: accent,
                      backgroundColor: accent.withValues(alpha: 0.15),
                    ),
                  ),
                  Text('$_testLeft',
                      style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              )
            : Icon(Icons.play_circle_outline_rounded,
                key: const ValueKey('play'), color: accent, size: 30),
      ),
    );
  }

  Future<void> _testAlarm() async {
    HapticFeedback.lightImpact();
    try {
      await platform.invokeMethod('testAlarm', {'seconds': 10});
      if (!mounted) return;
      setState(() => _testLeft = 10);
      _testTimer?.cancel();
      _testTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _testLeft--);
        if (_testLeft <= 0) t.cancel();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not set test alarm: $e')));
      }
    }
  }

  /// Row of colour dots; the chosen one has a ring + check.
  Widget _accentPicker(ThemeProvider tp) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 14,
      runSpacing: 12,
      children: [
        for (var i = 0; i < ThemeProvider.accents.length; i++)
          Builder(builder: (_) {
            final a = ThemeProvider.accents[i];
            final color = isDark ? a.dark : a.light;
            final sel = tp.accentIndex == i;
            return Tooltip(
              message: a.name,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  tp.setAccent(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: sel ? color : Colors.transparent, width: 2),
                  ),
                  child: Container(
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: sel
                        ? Icon(Icons.check_rounded, size: 18, color: isDark ? Colors.black : Colors.white)
                        : null,
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _sectionHeader(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 13, letterSpacing: 1),
        ),
      );

  Widget _row({
    required String title,
    String? subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    final dim = Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: dim, fontSize: 13)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}
