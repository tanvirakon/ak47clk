// lib/alarm_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'clock_widgets.dart';
import 'wheel_time_picker.dart';

/// True while alarm cards are being selected (HomeShell hides the tab bar + gear, locks swiping).
final ValueNotifier<bool> alarmSelecting = ValueNotifier(false);

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  _AlarmPageState createState() => _AlarmPageState();
}

/// One interval group as stored natively (AlarmStore). Every alarm has a unique id.
class AlarmGroup {
  final int id;
  final int? fromHour, fromMinute, toHour, toMinute, interval;
  final List<Map<String, dynamic>> alarms; // {id, hour, minute, formattedTime}
  final bool single; // normal alarm (not an interval range)
  final String? label;
  final int days; // repeat bitmask: bit = weekday % 7 (Sun 0 .. Sat 6); 0 = Once
  final int skipUntil, skipAt; // "off for next ring only"
  final int? nextAt; // next ring (epoch ms) from native, after skips
  final int? snoozeAt; // pending snooze (epoch ms)
  bool isEnabled;
  bool isExpanded;

  AlarmGroup({
    required this.id,
    this.single = false,
    this.label,
    this.days = 0,
    this.skipUntil = 0,
    this.skipAt = 0,
    this.nextAt,
    this.snoozeAt,
    this.fromHour,
    this.fromMinute,
    this.toHour,
    this.toMinute,
    this.interval,
    required this.alarms,
    required this.isEnabled,
    this.isExpanded = false,
  });

  bool get isInterval => fromHour != null && toHour != null && interval != null;
  bool get repeats => days != 0;
  bool get isSkipping => isEnabled && skipUntil > DateTime.now().millisecondsSinceEpoch;
  bool get isSnoozed => snoozeAt != null && snoozeAt! > DateTime.now().millisecondsSinceEpoch;

  /// Switch shows ON while enabled, or while a snooze is still waiting (even if a Once alarm already rang).
  bool get switchOn => isEnabled || isSnoozed;

  /// Chip order Sat → Fri, as (bit, short name).
  static const weekOrder = [(6, 'Sat'), (0, 'Sun'), (1, 'Mon'), (2, 'Tue'), (3, 'Wed'), (4, 'Thu'), (5, 'Fri')];

  static String repeatText(int days) {
    if (days == 0) return 'Once';
    if (days == 0x7F) return 'Daily';
    return weekOrder.where((d) => days & (1 << d.$1) != 0).map((d) => d.$2).join(', ');
  }

  /// "today" / "tomorrow" / "Thu"
  static String dayWord(DateTime t) {
    final now = DateTime.now();
    final d = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (d == 0) return 'today';
    if (d == 1) return 'tomorrow';
    return DateFormat('EEE').format(t);
  }

  /// True if the range wraps past midnight (e.g. 11 PM – 1 AM).
  bool get crossesMidnight =>
      isInterval && (toHour! * 60 + toMinute!) < (fromHour! * 60 + fromMinute!);

  String get title {
    if (single && alarms.isNotEmpty) return alarms.first['formattedTime'] as String;
    if (!isInterval) return 'Individual alarms';
    return '${_fmt(fromHour!, fromMinute!)} – ${_fmt(toHour!, toMinute!)}';
  }

  static String _fmt(int h, int m) =>
      DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));

  /// Minutes past midnight of the first alarm (for sorting the list by time).
  int get sortKey {
    if (isInterval) return fromHour! * 60 + fromMinute!;
    if (alarms.isEmpty) return 0;
    return (alarms.first['hour'] as int) * 60 + (alarms.first['minute'] as int);
  }

  factory AlarmGroup.fromJson(Map<String, dynamic> j) => AlarmGroup(
        id: j['id'] as int,
        single: j['single'] as bool? ?? false,
        label: j['label'] as String?,
        days: (j['days'] as num?)?.toInt() ?? 0,
        skipUntil: (j['skipUntil'] as num?)?.toInt() ?? 0,
        skipAt: (j['skipAt'] as num?)?.toInt() ?? 0,
        nextAt: (j['nextAt'] as num?)?.toInt(),
        snoozeAt: (j['snoozeAt'] as num?)?.toInt(),
        fromHour: j['fromHour'] as int?,
        fromMinute: j['fromMinute'] as int?,
        toHour: j['toHour'] as int?,
        toMinute: j['toMinute'] as int?,
        interval: j['interval'] as int?,
        isEnabled: j['enabled'] as bool? ?? true,
        alarms: (j['alarms'] as List).map((a) {
          final m = Map<String, dynamic>.from(a as Map);
          m['formattedTime'] = _fmt(m['hour'] as int, m['minute'] as int);
          return m;
        }).toList(),
      );
}

class _AlarmPageState extends State<AlarmPage> with WidgetsBindingObserver {
  /// Missing permission keys from native, shown as tappable banners (no popups on launch).
  List<String> _missingPerms = [];

  static const _permInfo = <String, (IconData, String, String)>{
    'notifications': (Icons.notifications_none_rounded, 'Allow notifications',
        'Needed to show the alarm and timer.'),
    'exactAlarm': (Icons.alarm_on_outlined, 'Allow alarms & reminders',
        'So alarms ring at the exact time.'),
    'fullScreen': (Icons.fullscreen_rounded, 'Allow full-screen alarms',
        'Shows the ring screen when the phone is locked.'),
    'overlay': (Icons.layers_outlined, 'Display over other apps',
        'Lets the alarm open on top of other apps.'),
    'battery': (Icons.battery_alert_outlined, 'Remove battery restriction',
        'Stops the phone from delaying or killing alarms.'),
    'miuiLockScreen': (Icons.lock_outline, 'Show on lock screen',
        'Allow "Show on Lock screen" and "Display pop-up windows while running in the background".'),
  };

  Future<void> _checkLockScreenPermission() async {
    try {
      final list = (await platform.invokeMethod<List>('missingPermissions') ?? [])
          .cast<String>()
          .where(_permInfo.containsKey)
          .toList();
      if (mounted && list.join(',') != _missingPerms.join(',')) {
        setState(() => _missingPerms = list);
      }
    } catch (_) {}
  }

  // Re-check when user comes back from the MIUI permission screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLockScreenPermission();
      _loadAlarms(); // a single alarm may have rung and switched itself off
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    alarmSelecting.value = false;
    _labelCtrl.dispose();
    super.dispose();
  }

  Widget _permissionBanner(String key) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber = isDark ? const Color(0xFFFFCC80) : const Color(0xFF9A5B00);
    final (icon, title, sub) = _permInfo[key]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: amber.withValues(alpha: isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await platform.invokeMethod('openPermission', {'key': key});
            // Re-check shortly after (system dialogs may not trigger a resume).
            Future.delayed(const Duration(seconds: 1), _checkLockScreenPermission);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Icon(icon, color: amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(color: amber, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(color: amber.withValues(alpha: 0.85), fontSize: 13)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: amber),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const platform = MethodChannel('com.example.ak47clk/alarm');

  TimeOfDay _fromTime = TimeOfDay.now();
  TimeOfDay _toTime = TimeOfDay.now();
  int _intervalMinutes = 2;
  List<AlarmGroup> _alarmGroups = [];

  // Single (one-time) alarm draft
  bool _singleMode = true;
  TimeOfDay _singleTime = TimeOfDay.now();
  final TextEditingController _labelCtrl = TextEditingController();
  int _days = 0; // repeat draft (0 = Once), shared by single + interval

  // Long-press selection (delete several at once)
  bool _selecting = false;
  final Set<int> _selected = {};

  void _enterSelect(AlarmGroup g) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(g.id);
    });
    alarmSelecting.value = true;
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    alarmSelecting.value = false;
  }

  void _toggleSelected(AlarmGroup g) {
    HapticFeedback.selectionClick();
    setState(() => _selected.contains(g.id) ? _selected.remove(g.id) : _selected.add(g.id));
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _alarmGroups.length) {
        _selected.clear();
      } else {
        _selected.addAll(_alarmGroups.map((g) => g.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toSet();
    if (ids.isEmpty) return;
    final count = _alarmGroups.where((g) => ids.contains(g.id)).fold<int>(0, (n, g) => n + g.alarms.length);
    setState(() => _alarmGroups.removeWhere((g) => ids.contains(g.id)));
    _exitSelect();
    try {
      for (final id in ids) {
        await platform.invokeMethod('deleteGroup', {'groupId': id});
      }
      _toast(count == 1 ? 'Alarm deleted' : '$count alarms deleted');
    } catch (e) {
      _toast('Failed to delete: $e');
    }
    await _loadAlarms();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLockScreenPermission();
    _loadAlarms();

    // Initialize end time to be 1 hour after start time
    final now = TimeOfDay.now();
    _fromTime = now;
    _toTime = TimeOfDay(hour: (now.hour + 1) % 24, minute: now.minute);
  }

  // ---------- data (all stored natively in AlarmStore) ----------

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadAlarms() async {
    try {
      final raw = await platform.invokeMethod<String>('getGroups') ?? '[]';
      final expanded = {for (final g in _alarmGroups) g.id: g.isExpanded};
      final groups = (jsonDecode(raw) as List)
          .map((j) => AlarmGroup.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
      for (final g in groups) {
        g.isExpanded = expanded[g.id] ?? false;
      }
      groups.sort((a, b) => a.sortKey.compareTo(b.sortKey)); // one list, by time
      if (mounted) {
        setState(() {
          _alarmGroups = groups;
          _selected.removeWhere((id) => !groups.any((g) => g.id == id));
        });
      }
    } catch (e) {
      debugPrint('Failed to load alarms: $e');
    }
  }

  /// Switch tapped. Turning OFF a repeating alarm asks: off for the next ring only, or fully off.
  Future<void> _onSwitch(AlarmGroup group) async {
    // Once alarm that already rang but is snoozed: switch off = stop the snooze.
    if (!group.isEnabled && group.isSnoozed) {
      await _cancelSnooze(group);
      return;
    }
    if (!group.isEnabled || !group.repeats) {
      final wasSnoozed = group.isSnoozed;
      await _toggleAlarmGroup(group); // turning off also cancels its snooze (native)
      if (wasSnoozed) _toast('Alarm off, snooze cancelled');
      return;
    }
    final next = group.nextAt == null ? null : DateTime.fromMillisecondsSinceEpoch(group.nextAt!);
    final skipping = group.isSkipping;
    final choice = await _offSheet(group, next, skipping);
    if (choice == 'snooze') {
      await _cancelSnooze(group);
    } else if (choice == 'off') {
      await _toggleAlarmGroup(group);
    } else if (choice == 'skip' && next != null) {
      try {
        await platform.invokeMethod('skipNext', {'groupId': group.id});
        _toast('Skipping ${AlarmGroup.dayWord(next)} ${DateFormat('h:mm a').format(next)}');
      } catch (e) {
        _toast('Failed: $e');
      }
      await _loadAlarms();
    } else if (choice == 'undo') {
      await platform.invokeMethod('setGroupEnabled', {'groupId': group.id, 'enabled': true});
      await _loadAlarms();
      _toast('Skip cancelled');
    }
  }

  Future<void> _cancelSnooze(AlarmGroup group) async {
    try {
      await platform.invokeMethod('cancelSnooze', {'groupId': group.id});
      _toast('Snooze cancelled');
    } catch (e) {
      _toast('Failed: $e');
    }
    await _loadAlarms();
  }

  Future<String?> _offSheet(AlarmGroup group, DateTime? next, bool skipping) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? Colors.white54 : Colors.black54;
    final accent = _accent(context);
    Widget option(BuildContext c, IconData icon, String title, String sub, String value) => ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          leading: Icon(icon, color: accent),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(sub, style: TextStyle(color: dim)),
          onTap: () => Navigator.pop(c, value),
        );
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: isDark ? const Color(0xFF1E1F23) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(group.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(AlarmGroup.repeatText(group.days), style: TextStyle(color: dim)),
              const SizedBox(height: 12),
              if (group.isSnoozed)
                option(c, Icons.snooze_rounded, 'Cancel snooze',
                    'Stops the ${DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(group.snoozeAt!))} snooze, alarm stays on',
                    'snooze'),
              if (skipping)
                option(c, Icons.undo_rounded, 'Undo skip', 'Ring as usual again', 'undo')
              else if (next != null)
                option(c, Icons.event_busy_outlined, 'Off for ${AlarmGroup.dayWord(next)} only',
                    'Skips ${DateFormat('EEE h:mm a').format(next)}, then rings as usual', 'skip'),
              option(c, Icons.alarm_off_rounded, 'Turn off', 'Stays off until you switch it on', 'off'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleAlarmGroup(AlarmGroup group) async {
    final newState = !group.isEnabled;
    setState(() => group.isEnabled = newState);
    try {
      await platform.invokeMethod('setGroupEnabled', {'groupId': group.id, 'enabled': newState});
    } catch (e) {
      setState(() => group.isEnabled = !newState); // revert
      _toast('Failed to update alarm: $e');
    }
    await _loadAlarms(); // refresh next ring / skip note
  }

  Future<void> _deleteAlarm(Map<String, dynamic> alarm) async {
    try {
      await platform.invokeMethod('deleteAlarm', {'alarmId': alarm['id']});
    } catch (e) {
      _toast('Failed to delete alarm: $e');
    }
    await _loadAlarms();
  }

  Future<void> _setIntervalAlarms() async {
    try {
      final count = await platform.invokeMethod<int>('createGroup', {
        'fromHour': _fromTime.hour,
        'fromMinute': _fromTime.minute,
        'toHour': _toTime.hour,
        'toMinute': _toTime.minute,
        'interval': _intervalMinutes,
        'days': _days,
      });
      await _loadAlarms();
      _toast('$count alarms set, every $_intervalMinutes min');
    } catch (e) {
      _toast('Failed to set alarms: $e');
    }
  }

  Future<void> _saveSingle({AlarmGroup? edit}) async {
    final label = _labelCtrl.text.trim();
    try {
      final res = await platform.invokeMethod(edit == null ? 'createSingle' : 'updateSingle', {
        if (edit != null) 'groupId': edit.id,
        'hour': _singleTime.hour,
        'minute': _singleTime.minute,
        'label': label.isEmpty ? null : label,
        'days': _days,
      });
      await _loadAlarms();
      final id = edit?.id ?? (res is int ? res : null);
      final g = _alarmGroups.where((g) => g.id == id).firstOrNull;
      final now = DateTime.now();
      var at = DateTime(now.year, now.month, now.day, _singleTime.hour, _singleTime.minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      if (g?.nextAt != null) at = DateTime.fromMillisecondsSinceEpoch(g!.nextAt!); // respects repeat days
      _toast('Alarm ${_inText(at.difference(now))}');
    } catch (e) {
      _toast('Failed to set alarm: $e');
    }
  }

  // ---------- UI ----------

  /// Next upcoming alarm time across enabled groups (today or tomorrow).
  DateTime? _nextAlarm() {
    final now = DateTime.now();
    DateTime? best;
    for (final g in _alarmGroups.where((g) => g.isSnoozed)) {
      final t = DateTime.fromMillisecondsSinceEpoch(g.snoozeAt!);
      if (best == null || t.isBefore(best)) best = t;
    }
    for (final g in _alarmGroups.where((g) => g.isEnabled)) {
      // Native knows repeat days + skips; use its answer while it's still ahead.
      if (g.nextAt != null && g.nextAt! > now.millisecondsSinceEpoch) {
        final t = DateTime.fromMillisecondsSinceEpoch(g.nextAt!);
        if (best == null || t.isBefore(best)) best = t;
        continue;
      }
      for (final a in g.alarms) {
        final h = a['hour'], m = a['minute'];
        if (h is! int || m is! int) continue;
        var t = DateTime(now.year, now.month, now.day, h, m);
        if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
        if (best == null || t.isBefore(best)) best = t;
      }
    }
    return best;
  }

  String _countdownText() {
    final next = _nextAlarm();
    if (next == null) return 'No upcoming alarms';
    return 'Next alarm ${_inText(next.difference(DateTime.now()))}';
  }

  /// "in 5 min" / "in 3h 20m" / "in 2d 4h"
  static String _inText(Duration d) {
    final days = d.inDays, h = d.inHours % 24, m = d.inMinutes % 60;
    if (days > 0) return 'in ${days}d ${h}h';
    if (h == 0) return 'in ${m == 0 ? 1 : m} min';
    return 'in ${h}h ${m}m';
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary; // accent chosen in Settings

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dim = isDark ? Colors.white54 : Colors.black54;

    return PopScope(
      canPop: !_selecting, // back button leaves selection first
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelect();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title removed; settings gear lives in HomeShell (fixed across tabs). Right pad clears it.
              SizedBox(
                height: 56,
                child: _selecting
                    ? _selectionHeader()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 64, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(_countdownText(), style: TextStyle(color: dim, fontSize: 15)),
                        ),
                      ),
              ),
              if (!_selecting) ...[
                for (final key in _missingPerms) _permissionBanner(key),
                if (_missingPerms.isNotEmpty) const SizedBox(height: 4),
              ],
              Expanded(child: _buildAlarmsList()),
            ],
          ),
        ),
        // RepaintBoundary: the breathing glow repaints only the button, not the whole page.
        floatingActionButton: _selecting
            ? null
            : RepaintBoundary(
                child: _BubbleFab(
                  color: _accent(context),
                  onTap: _openAddBubble,
                ),
              ),
        bottomNavigationBar: _selecting ? _deleteBar() : null,
      ),
    );
  }

  /// ✕ | "N items selected" | select all
  Widget _selectionHeader() {
    final n = _selected.length;
    final all = n == _alarmGroups.length && n > 0;
    return Row(
      children: [
        const SizedBox(width: 4),
        IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: _exitSelect),
        Expanded(
          child: Text(
            n == 0 ? 'Select items' : '$n item${n == 1 ? '' : 's'} selected',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
        IconButton(
          icon: Icon(all ? Icons.remove_done_rounded : Icons.checklist_rounded),
          tooltip: all ? 'Deselect all' : 'Select all',
          onPressed: _toggleSelectAll,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// Bottom bar in selection mode (replaces the tab bar).
  Widget _deleteBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = _selected.isNotEmpty;
    final fg = (isDark ? Colors.white : Colors.black87).withValues(alpha: enabled ? 1 : 0.35);
    return Material(
      color: Theme.of(context).navigationBarTheme.backgroundColor ??
          (isDark ? const Color(0xFF16171A) : const Color(0xFFF7F8FA)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled ? _deleteSelected : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded, color: fg),
                    const SizedBox(height: 2),
                    Text('Delete', style: TextStyle(color: fg, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Round check marker shown in place of the switch while selecting.
  Widget _selectMark(AlarmGroup g) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sel = _selected.contains(g.id);
    return SizedBox(
      width: 60,
      height: 48,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: sel ? _accent(context) : (isDark ? Colors.white24 : Colors.black12),
          ),
          child: sel
              ? Icon(Icons.check_rounded, size: 18, color: isDark ? Colors.black : Colors.white)
              : null,
        ),
      ),
    );
  }

  Widget _buildAlarmsList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? Colors.white38 : Colors.black38;

    if (_alarmGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SleepyClock(),
            const SizedBox(height: 16),
            Text('No alarms yet',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text('Tap + to set your first alarm', style: TextStyle(color: dim, fontSize: 14)),
            const SizedBox(height: 60), // keeps art above the + button visually
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: _alarmGroups.length,
      itemBuilder: (context, i) => _groupCard(_alarmGroups[i]),
    );
  }

  Widget _groupCard(AlarmGroup group) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1F23) : const Color(0xFFF3F4F7);
    final fg = isDark ? Colors.white : Colors.black87;
    final dim = isDark ? Colors.white54 : Colors.black54;
    final on = group.switchOn; // also ON while a snooze is waiting
    final bright = on && !group.isSkipping; // skipped = switch on, text dimmed

    // Subtitle: "every 10 min · 7 alarms · Daily" for interval groups
    String subtitle = '${group.alarms.length} alarm${group.alarms.length == 1 ? '' : 's'}';
    if (group.isInterval) {
      subtitle = 'every ${group.interval} min · $subtitle';
      if (group.crossesMidnight) subtitle += ' · overnight';
    }
    subtitle += ' · ${_repeatSub(group)}';

    // Long-press = select mode (delete); swiping left/right always changes tabs.
    return Container(
        key: ValueKey(group.id),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onLongPress: _selecting ? null : () => _enterSelect(group),
            onTap: _selecting
                ? () => _toggleSelected(group)
                : group.single
                    ? () => _openAddBubble(edit: group)
                    : () => setState(() => group.isExpanded = !group.isExpanded),
            child: group.single ? _singleContent(group, fg, dim) : Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.title,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w300,
                                color: bright ? fg : dim,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(subtitle, style: TextStyle(color: group.isSnoozed ? _accent(context) : dim, fontSize: 13)),
                          ],
                        ),
                      ),
                      if (_selecting)
                        _selectMark(group)
                      else
                        BouncySwitch(
                          value: on,
                          onChanged: (_) => _onSwitch(group),
                        ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: group.isExpanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 14, right: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: group.alarms
                                  .map((a) => _alarmChip(a, isDark, dim))
                                  .toList(),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  /// "Daily" / "Sat, Mon" / "Once", or "Skipping tomorrow" while a skip is active.
  String _repeatSub(AlarmGroup g) {
    if (g.isSnoozed) {
      return 'Snoozed · rings ${DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(g.snoozeAt!))}';
    }
    if (g.isSkipping && g.skipAt > 0) {
      return 'Skipping ${AlarmGroup.dayWord(DateTime.fromMillisecondsSinceEpoch(g.skipAt))}';
    }
    return AlarmGroup.repeatText(g.days);
  }

  /// Repeat section in the add card: Once | Daily chips, then Sat → Fri day circles.
  Widget _repeatPicker(StateSetter setLocal, bool isDark, Color accent, Color fg, Color dim) {
    final onAccent = isDark ? Colors.black : Colors.white;
    final off = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05);

    Widget chip(String text, int value) {
      final sel = _days == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(text),
          selected: sel,
          showCheckmark: false,
          shape: const StadiumBorder(),
          selectedColor: accent.withValues(alpha: 0.25),
          side: BorderSide(color: sel ? accent : (isDark ? Colors.white24 : Colors.black12)),
          onSelected: (_) => setLocal(() => _days = value),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Repeat', style: TextStyle(color: dim, fontSize: 14)),
        const SizedBox(height: 10),
        Row(children: [chip('Once', 0), chip('Daily', 0x7F)]),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final (bit, name) in AlarmGroup.weekOrder)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setLocal(() => _days ^= 1 << bit);
                    },
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _days & (1 << bit) != 0 ? accent : off,
                        ),
                        alignment: Alignment.center,
                        child: FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _days & (1 << bit) != 0 ? onAccent : fg,
                                )),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Card body for a normal one-time alarm: big time, label, switch.
  Widget _singleContent(AlarmGroup group, Color fg, Color dim) {
    final on = group.switchOn; // also ON while a snooze is waiting
    final bright = on && !group.isSkipping;
    final a = group.alarms.isNotEmpty ? group.alarms.first : null;
    final dt = DateTime(2000, 1, 1, (a?['hour'] as int?) ?? 0, (a?['minute'] as int?) ?? 0);
    final sub = (group.label?.isNotEmpty ?? false) ? '${group.label} · ${_repeatSub(group)}' : _repeatSub(group);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(DateFormat('h:mm').format(dt),
                        style: TextStyle(fontSize: 38, fontWeight: FontWeight.w300, color: bright ? fg : dim)),
                    const SizedBox(width: 6),
                    Text(DateFormat('a').format(dt),
                        style: TextStyle(fontSize: 14, color: dim)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: group.isSnoozed ? _accent(context) : dim, fontSize: 13)),
              ],
            ),
          ),
          if (_selecting)
            _selectMark(group)
          else
            BouncySwitch(value: on, onChanged: (_) => _onSwitch(group)),
        ],
      ),
    );
  }

  Widget _alarmChip(Map<String, dynamic> alarm, bool isDark, Color dim) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(alarm['formattedTime'].toString(), style: const TextStyle(fontSize: 13)),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: Icon(Icons.close, color: dim),
            onPressed: () => _deleteAlarm(alarm),
          ),
        ],
      ),
    );
  }

  /// Opens the "liquid bubble" add card: grows out of the + button with an elastic pop.
  Future<void> _openAddBubble({AlarmGroup? edit}) async {
    // Fresh draft each time; prefill when editing a single alarm.
    if (edit != null && edit.alarms.isNotEmpty) {
      _singleMode = true;
      _singleTime = TimeOfDay(
          hour: edit.alarms.first['hour'] as int, minute: edit.alarms.first['minute'] as int);
      _labelCtrl.text = edit.label ?? '';
      _days = edit.days;
    } else {
      _singleTime = TimeOfDay.now();
      _labelCtrl.clear();
      _days = 0; // Once by default
    }
    final saved = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 320),
      // Card built once here (not every animation frame) and cached in its own layer.
      pageBuilder: (ctx, _, __) => Padding(
        // lift the card above the keyboard when typing a label
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: RepaintBoundary(child: _addBubbleCard(ctx, edit: edit)),
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: curved,
          alignment: Alignment.bottomRight,
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
    if (saved != true) return;
    if (_singleMode) {
      await _saveSingle(edit: edit);
    } else {
      await _setIntervalAlarms();
    }
  }

  /// Single | Interval segmented switch at the top of the add card.
  Widget _modeSwitch(bool isDark, Color accent, Color fg, Color dim, void Function(bool) onPick) {
    Widget seg(String text, bool single) {
      final sel = _singleMode == single;
      return Expanded(
        child: GestureDetector(
          onTap: () => onPick(single),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: Text(text,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: sel ? (isDark ? Colors.black : Colors.white) : dim,
                )),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(children: [seg('Single', true), seg('Interval', false)]),
    );
  }

  Widget _addBubbleCard(BuildContext ctx, {AlarmGroup? edit}) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black87;
    final dim = isDark ? Colors.white54 : Colors.black54;
    final accent = _accent(ctx);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: SizedBox(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF2A2D35), const Color(0xFF1A1C21)]
                      : [const Color(0xFFFFFFFF), const Color(0xFFF1F3F8)],
                ),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.white,
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: StatefulBuilder(
                  builder: (ctx, setLocal) {
                    Future<void> pick(bool isFrom) async {
                      final picked = await showWheelTimePicker(
                        ctx,
                        initialTime: isFrom ? _fromTime : _toTime,
                        title: isFrom ? 'Start time' : 'End time',
                      );
                      if (picked != null) {
                        setLocal(() => isFrom ? _fromTime = picked : _toTime = picked);
                        setState(() {});
                      }
                    }

                    Future<void> pickSingle() async {
                      final picked = await showWheelTimePicker(
                        ctx,
                        initialTime: _singleTime,
                        title: 'Alarm time',
                      );
                      if (picked != null) setLocal(() => _singleTime = picked);
                    }

                    final singleBody = <Widget>[
                      Center(child: _timeTile('Rings at', _singleTime, pickSingle, fg, dim, big: true)),
                      // Label field removed from UI for now; native label support kept.
                      const SizedBox(height: 16),
                      _repeatPicker(setLocal, isDark, accent, fg, dim),
                    ];

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (edit == null)
                          _modeSwitch(isDark, accent, fg, dim, (s) {
                            FocusScope.of(ctx).unfocus();
                            setLocal(() => _singleMode = s);
                          })
                        else
                          Text('Edit alarm', style: TextStyle(color: dim, fontSize: 14)),
                        const SizedBox(height: 16),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _singleMode ? singleBody : [
                        Row(
                          children: [
                            Expanded(child: _timeTile('From', _fromTime, () => pick(true), fg, dim)),
                            Icon(Icons.arrow_forward, color: dim, size: 20),
                            Expanded(child: _timeTile('To', _toTime, () => pick(false), fg, dim)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text('Repeat every', style: TextStyle(color: dim, fontSize: 14)),
                        const SizedBox(height: 10),
                        Row(
                          children: [2, 5, 8, 10].map((v) {
                            final sel = v == _intervalMinutes;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('$v min'),
                                selected: sel,
                                showCheckmark: false,
                                shape: const StadiumBorder(),
                                selectedColor: accent.withValues(alpha: 0.25),
                                side: BorderSide(color: sel ? accent : (isDark ? Colors.white24 : Colors.black12)),
                                onSelected: (_) {
                                  setLocal(() => _intervalMinutes = v);
                                  setState(() {});
                                },
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        _repeatPicker(setLocal, isDark, accent, fg, dim),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _pill('Cancel', isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06), fg,
                                  () => Navigator.pop(ctx, false)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _pill(
                                  edit != null ? 'Save' : (_singleMode ? 'Set alarm' : 'Set alarms'),
                                  accent, isDark ? Colors.black : Colors.white,
                                  () => Navigator.pop(ctx, true)),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _timeTile(String label, TimeOfDay t, VoidCallback onTap, Color fg, Color dim,
      {bool big = false}) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: dim, fontSize: 13)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$h:${t.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: big ? 56 : 34, fontWeight: FontWeight.w300, color: fg)),
                const SizedBox(width: 4),
                Text(t.period == DayPeriod.am ? 'AM' : 'PM',
                    style: TextStyle(fontSize: 13, color: dim)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(text, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}

/// Round + button with a soft "breathing" glow and a squishy press.
class _BubbleFab extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;
  const _BubbleFab({required this.color, required this.onTap});

  @override
  State<_BubbleFab> createState() => _BubbleFabState();
}

class _BubbleFabState extends State<_BubbleFab> with SingleTickerProviderStateMixin {
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
  bool _pressed = false;

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: AnimatedBuilder(
          animation: _breath,
          builder: (_, child) => Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                colors: [Color.lerp(widget.color, Colors.white, 0.35)!, widget.color],
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.25 + 0.2 * _breath.value),
                  blurRadius: 18 + 10 * _breath.value,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          ),
          child: Icon(
            Icons.add,
            size: 30,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0E0F12)
                : Colors.white,
          ),
        ),
      ),
    );
  }
}
