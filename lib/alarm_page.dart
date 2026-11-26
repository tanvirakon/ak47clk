// lib/alarm_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'wheel_time_picker.dart';

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
  final bool single; // normal one-time alarm
  final String? label;
  bool isEnabled;
  bool isExpanded;

  AlarmGroup({
    required this.id,
    this.single = false,
    this.label,
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
  bool _lockScreenOk = true;

  Future<void> _checkLockScreenPermission() async {
    try {
      final ok = await platform.invokeMethod<bool>('lockScreenPermissionOk') ?? true;
      if (mounted && ok != _lockScreenOk) setState(() => _lockScreenOk = ok);
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
    _labelCtrl.dispose();
    super.dispose();
  }

  Widget _lockScreenBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber = isDark ? const Color(0xFFFFCC80) : const Color(0xFF9A5B00);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: amber.withValues(alpha: isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => platform.invokeMethod('openLockScreenPermission'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Alarm can\'t show on lock screen',
                          style: TextStyle(color: amber, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'Tap → allow "Show on Lock screen" and "Display pop-up windows while running in the background".',
                        style: TextStyle(color: amber.withValues(alpha: 0.85), fontSize: 13),
                      ),
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
      if (mounted) setState(() => _alarmGroups = groups);
    } catch (e) {
      debugPrint('Failed to load alarms: $e');
    }
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
  }

  Future<void> _deleteAlarmGroup(AlarmGroup group) async {
    setState(() => _alarmGroups.removeWhere((g) => g.id == group.id));
    try {
      await platform.invokeMethod('deleteGroup', {'groupId': group.id});
      _toast(group.alarms.length == 1 ? 'Alarm deleted' : '${group.alarms.length} alarms deleted');
    } catch (e) {
      _toast('Failed to delete: $e');
    }
    await _loadAlarms();
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
      await platform.invokeMethod(edit == null ? 'createSingle' : 'updateSingle', {
        if (edit != null) 'groupId': edit.id,
        'hour': _singleTime.hour,
        'minute': _singleTime.minute,
        'label': label.isEmpty ? null : label,
      });
      await _loadAlarms();
      final now = DateTime.now();
      var at = DateTime(now.year, now.month, now.day, _singleTime.hour, _singleTime.minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      final d = at.difference(now);
      final h = d.inHours, m = d.inMinutes % 60;
      _toast(h == 0 ? 'Alarm in ${m == 0 ? 1 : m} min' : 'Alarm in ${h}h ${m}m');
    } catch (e) {
      _toast('Failed to set alarm: $e');
    }
  }

  // ---------- UI ----------

  /// Next upcoming alarm time across enabled groups (today or tomorrow).
  DateTime? _nextAlarm() {
    final now = DateTime.now();
    DateTime? best;
    for (final g in _alarmGroups.where((g) => g.isEnabled)) {
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
    final d = next.difference(DateTime.now());
    final h = d.inHours, m = d.inMinutes % 60;
    if (h == 0) return 'Next alarm in ${m == 0 ? 1 : m} min';
    return 'Next alarm in ${h}h ${m}m';
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF8AB4F8)
          : const Color(0xFF3B6FD8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dim = isDark ? Colors.white54 : Colors.black54;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title removed; settings gear lives in HomeShell (fixed across tabs). Right pad clears it.
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 64, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_countdownText(), style: TextStyle(color: dim, fontSize: 15)),
                ),
              ),
            ),
            if (!_lockScreenOk) _lockScreenBanner(),
            Expanded(child: _buildAlarmsList()),
          ],
        ),
      ),
      // RepaintBoundary: the breathing glow repaints only the button, not the whole page.
      floatingActionButton: RepaintBoundary(
        child: _BubbleFab(
          color: _accent(context),
          onTap: _openAddBubble,
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
            Icon(Icons.alarm_off_outlined, size: 56, color: dim),
            const SizedBox(height: 12),
            Text('No alarms yet', style: TextStyle(color: dim, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Tap + to add one', style: TextStyle(color: dim, fontSize: 13)),
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
    final on = group.isEnabled;

    // Subtitle: "every 10 min · 7 alarms" for interval groups
    String subtitle = '${group.alarms.length} alarm${group.alarms.length == 1 ? '' : 's'}';
    if (group.isInterval) {
      subtitle = 'every ${group.interval} min · $subtitle';
      if (group.crossesMidnight) subtitle += ' · overnight';
    }

    return Dismissible(
      key: ValueKey(group.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(right: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: const Color(0xFFD9534F),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Delete alarms?'),
              content: Text(group.title),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
              ],
            ),
          ) ??
          false,
      onDismissed: (_) => _deleteAlarmGroup(group),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: group.single
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
                                color: on ? fg : dim,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(subtitle, style: TextStyle(color: dim, fontSize: 13)),
                          ],
                        ),
                      ),
                      Switch(
                        value: on,
                        onChanged: (_) => _toggleAlarmGroup(group),
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
      ),
    );
  }

  /// Card body for a normal one-time alarm: big time, label, switch.
  Widget _singleContent(AlarmGroup group, Color fg, Color dim) {
    final on = group.isEnabled;
    final a = group.alarms.isNotEmpty ? group.alarms.first : null;
    final dt = DateTime(2000, 1, 1, (a?['hour'] as int?) ?? 0, (a?['minute'] as int?) ?? 0);
    final sub = (group.label?.isNotEmpty ?? false) ? '${group.label} · Once' : 'Once';
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
                        style: TextStyle(fontSize: 38, fontWeight: FontWeight.w300, color: on ? fg : dim)),
                    const SizedBox(width: 6),
                    Text(DateFormat('a').format(dt),
                        style: TextStyle(fontSize: 14, color: dim)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: dim, fontSize: 13)),
              ],
            ),
          ),
          Switch(value: on, onChanged: (_) => _toggleAlarmGroup(group)),
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
    } else {
      _singleTime = TimeOfDay.now();
      _labelCtrl.clear();
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
