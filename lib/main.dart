// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'home_shell.dart';
import 'theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'ak47clk',
            debugShowCheckedModeBanner: false,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const HomeShell(),
          );
        },
      ),
    );
  }

  // Shared accent (matches alarm_page _accent): calm blue, no Material purple.
  static const _lightAccent = Color(0xFF3B6FD8);
  static const _darkAccent = Color(0xFF8AB4F8);

  ThemeData _buildLightTheme() => _theme(
        brightness: Brightness.light,
        accent: _lightAccent,
        bg: const Color(0xFFFAFAFC),
        surface: const Color(0xFFF3F4F7),
        fg: const Color(0xFF1C1D21),
      );

  ThemeData _buildDarkTheme() => _theme(
        brightness: Brightness.dark,
        accent: _darkAccent,
        bg: const Color(0xFF0E0F12),
        surface: const Color(0xFF1E1F23),
        fg: const Color(0xFFECEDEF),
      );

  ThemeData _theme({
    required Brightness brightness,
    required Color accent,
    required Color bg,
    required Color surface,
    required Color fg,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: isDark ? Colors.black : Colors.white,
      surface: bg,
      onSurface: fg,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: bg,
      cardColor: surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (isDark ? Colors.black : Colors.white)
              : (isDark ? const Color(0xFF8E9099) : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent
              : (isDark ? const Color(0xFF2E3036) : const Color(0xFFD5D7DD)),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        labelStyle: TextStyle(color: fg, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A2C31) : const Color(0xFF1C1D21),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerColor: isDark ? Colors.white12 : Colors.black12,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: accent.withValues(alpha: isDark ? 0.22 : 0.14),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? accent : fg.withValues(alpha: 0.55),
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
              color: s.contains(WidgetState.selected) ? accent : fg.withValues(alpha: 0.55),
            )),
      ),
    );
  }
}

