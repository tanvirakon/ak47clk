// lib/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
            trailing: Switch(
              value: themeProvider.isDarkMode,
              onChanged: themeProvider.toggleTheme,
            ),
            onTap: () => themeProvider.toggleTheme(!themeProvider.isDarkMode),
          ),
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
        ],
      ),
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
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
            trailing,
          ],
        ),
      ),
    );
  }
}
