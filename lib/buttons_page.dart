// lib/buttons_page.dart
// Settings > Buttons while ringing: pick what Power / Vol + / Vol - do while an alarm rings.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'clock_widgets.dart';

const _channel = MethodChannel('com.example.ak47clk/alarm');

/// key -> (name in the UI)
const buttonNames = {'volUp': 'Volume +', 'volDown': 'Volume −', 'power': 'Power'};

/// value -> short label
const buttonActions = {
  'nothing': 'Nothing',
  'snooze5': 'Snooze 5 min',
  'snooze10': 'Snooze 10 min',
  'snooze15': 'Snooze 15 min',
  'silence': 'Silence',
  'off': 'Turn off',
};

Future<Map<String, String>> loadButtons() async {
  try {
    final raw = await _channel.invokeMethod<String>('getButtons') ?? '{}';
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final k in buttonNames.keys) k: (j[k] as String?) ?? 'nothing'};
  } catch (_) {
    return {for (final k in buttonNames.keys) k: 'nothing'};
  }
}

/// One-line summary for the Settings row ("Off" when nothing is set).
String buttonsSummary(Map<String, String> b) {
  final set = [
    for (final k in buttonNames.keys)
      if ((b[k] ?? 'nothing') != 'nothing') '${buttonNames[k]}: ${buttonActions[b[k]]}'
  ];
  return set.isEmpty ? 'Off' : set.join(' · ');
}

class ButtonsPage extends StatefulWidget {
  const ButtonsPage({super.key});

  @override
  State<ButtonsPage> createState() => _ButtonsPageState();
}

class _ButtonsPageState extends State<ButtonsPage> {
  Map<String, String> _b = {for (final k in buttonNames.keys) k: 'nothing'};

  @override
  void initState() {
    super.initState();
    loadButtons().then((b) {
      if (mounted) setState(() => _b = b);
    });
  }

  Future<void> _set(String key, String value) async {
    setState(() => _b = {..._b, key: value});
    try {
      await _channel.invokeMethod('setButton', {'key': key, 'value': value});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  String _desc(String key, String value) {
    switch (value) {
      case 'nothing':
        return key == 'power' ? 'Just turns the screen off' : 'Changes the alarm volume as usual';
      case 'silence':
        return 'Stops sound and vibration. Swipe to turn off or snooze';
      case 'off':
        return 'Turns the alarm off';
      default:
        return 'Timer and test alarm: turns off';
    }
  }

  Future<void> _pick(String key) async {
    HapticFeedback.selectionClick();
    final theme = Theme.of(context);
    final accent = accentOf(context);
    final dim = theme.brightness == Brightness.dark ? Colors.white54 : Colors.black54;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(28)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${buttonNames[key]} while ringing', style: TextStyle(color: dim, fontSize: 14)),
                ),
              ),
              for (final e in buttonActions.entries)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(e.value, style: const TextStyle(fontSize: 17)),
                  subtitle: Text(_desc(key, e.key), style: TextStyle(color: dim, fontSize: 13)),
                  trailing: _b[key] == e.key ? Icon(Icons.check_rounded, color: accent) : null,
                  onTap: () => Navigator.pop(ctx, e.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice != null && choice != _b[key]) _set(key, choice);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.brightness == Brightness.dark ? Colors.white54 : Colors.black54;
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
          const Text('Buttons while ringing', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w400)),
          const SizedBox(height: 8),
          Text('Tap a button on the phone to choose what it does when an alarm or timer rings.',
              style: TextStyle(color: dim, fontSize: 14)),
          const SizedBox(height: 32),
          Center(child: _phone()),
          const SizedBox(height: 32),
          if (_b.values.any((v) => v != 'nothing'))
            Center(
              child: TextButton(
                onPressed: () {
                  for (final k in buttonNames.keys) {
                    if (_b[k] != 'nothing') _set(k, 'nothing');
                  }
                },
                child: const Text('Reset all to Nothing'),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------- phone drawing ----------------
  static const double _pw = 150, _ph = 300; // phone body
  static const _slots = {
    // key: (top, height) on the right edge
    'volUp': (64.0, 46.0),
    'volDown': (118.0, 46.0),
    'power': (196.0, 36.0),
  };

  Widget _phone() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = accentOf(context);
    final body = isDark ? const Color(0xFF1E1F23) : const Color(0xFFF3F4F7);
    final rim = isDark ? Colors.white24 : Colors.black26;
    final fg = Theme.of(context).colorScheme.onSurface;
    final dim = isDark ? Colors.white38 : Colors.black38;

    return SizedBox(
      width: _pw + 6 + 150,
      height: _ph,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // body + screen
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: _pw,
              height: _ph,
              decoration: BoxDecoration(
                color: body,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: rim, width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.alarm_rounded, size: 40, color: accent),
                  const SizedBox(height: 8),
                  Text('7:00', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: fg)),
                  Text('ringing…', style: TextStyle(fontSize: 12, color: dim)),
                ],
              ),
            ),
          ),
          // side buttons + their labels
          for (final e in _slots.entries) ..._sideButton(e.key, e.value.$1, e.value.$2, accent, rim, fg, dim),
        ],
      ),
    );
  }

  List<Widget> _sideButton(String key, double top, double h, Color accent, Color rim, Color fg, Color dim) {
    final value = _b[key] ?? 'nothing';
    final active = value != 'nothing';
    final label = buttonActions[value]!;
    return [
      // the physical button
      Positioned(
        left: _pw - 1,
        top: top,
        child: GestureDetector(
          onTap: () => _pick(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 7,
            height: h,
            decoration: BoxDecoration(
              color: active ? accent : rim,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
            ),
          ),
        ),
      ),
      // label chip next to it
      Positioned(
        left: _pw + 16,
        top: top + h / 2 - 22,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pick(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 136,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: active ? accent.withValues(alpha: 0.5) : rim),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(buttonNames[key]!, style: TextStyle(fontSize: 11, color: dim)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? accent : fg)),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}
