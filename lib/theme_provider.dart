// lib/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One accent choice: a deeper shade for light mode, a softer one for dark mode.
class AccentOption {
  final String name;
  final Color light, dark;
  const AccentOption(this.name, this.light, this.dark);
}

class ThemeProvider extends ChangeNotifier {
  static const accents = [
    AccentOption('Blue', Color(0xFF3B6FD8), Color(0xFF8AB4F8)), // original
    AccentOption('Green', Color(0xFF1E8E5A), Color(0xFF7DD3A0)),
    AccentOption('Purple', Color(0xFF7B4FD6), Color(0xFFC3A6FF)),
    AccentOption('Orange', Color(0xFFD9661F), Color(0xFFFFB27A)),
    AccentOption('Pink', Color(0xFFC2407A), Color(0xFFF6A1C8)),
    AccentOption('Teal', Color(0xFF0E8A8A), Color(0xFF7ED9D6)),
  ];

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  int _accentIndex = 0;
  int get accentIndex => _accentIndex;
  AccentOption get accent => accents[_accentIndex];

  /// Prefs are loaded in main() before the first frame, so the right theme shows instantly (no flash).
  ThemeProvider(SharedPreferences prefs) {
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _accentIndex = (prefs.getInt('accentIndex') ?? 0).clamp(0, accents.length - 1);
  }

  Future<void> toggleTheme(bool value) async {
    _isDarkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }

  Future<void> setAccent(int i) async {
    _accentIndex = i.clamp(0, accents.length - 1);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accentIndex', _accentIndex);
  }
}
