// lib/stats/stats_engine.dart
// Turns the native ring log into sessions, days, score, streaks and badges.
// Pure Dart (no Flutter) so it is easy to unit test.
import 'dart:convert';
import 'dart:math' as math;

/// One logged event (see RingLog.kt).
class RingEvent {
  final int t; // ms
  final String type; // ring | snooze | off
  final int alarmId, groupId;
  final int run; // start of this run / morning (ms)
  final bool single;
  final bool fromSnooze; // ring came from a snooze
  final int snoozeMin;

  const RingEvent({
    required this.t,
    required this.type,
    required this.alarmId,
    required this.groupId,
    required this.run,
    this.single = true,
    this.fromSnooze = false,
    this.snoozeMin = 0,
  });

  factory RingEvent.fromJson(Map<String, dynamic> j) => RingEvent(
        t: (j['t'] as num).toInt(),
        type: j['type'] as String,
        alarmId: (j['a'] as num?)?.toInt() ?? -1,
        groupId: (j['g'] as num?)?.toInt() ?? -1,
        run: (j['run'] as num?)?.toInt() ?? (j['t'] as num).toInt(),
        single: j['single'] as bool? ?? true,
        fromSnooze: j['snz'] as bool? ?? false,
        snoozeMin: (j['min'] as num?)?.toInt() ?? 0,
      );

  static List<RingEvent> listFromJson(String raw) {
    final out = <RingEvent>[];
    for (final o in (jsonDecode(raw) as List)) {
      try {
        out.add(RingEvent.fromJson((o as Map).cast<String, dynamic>()));
      } catch (_) {} // skip broken entries
    }
    out.sort((a, b) => a.t.compareTo(b.t));
    return out;
  }
}

/// Points.
const int kCleanWake = 100; // woke on the first ring
const int kLateWake = 60; // got up eventually
const int kSnoozePenalty = 15;
const int kExtraRingPenalty = 10;
const int kFastBonus = 20; // reacted within 30 s
const int kFastMs = 30 * 1000;

/// One run of a group (single alarm, or one morning of an interval series).
class Session {
  final int groupId;
  final DateTime start;
  final bool single;
  final List<RingEvent> events;

  Session(this.groupId, this.start, this.single, this.events);

  int get rings => events.where((e) => e.type == 'ring').length;
  int get alarmRings => events.where((e) => e.type == 'ring' && !e.fromSnooze).length;
  int get snoozes => events.where((e) => e.type == 'snooze').length;

  /// Rings of later alarms in the series after the first one.
  int get extraRings => single ? 0 : math.max(0, alarmRings - 1);

  DateTime? get firstRingAt {
    final r = events.where((e) => e.type == 'ring');
    return r.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch(r.first.t);
  }

  /// Last turn-off of the run = when you got up.
  DateTime? get wokeAt {
    final r = events.where((e) => e.type == 'off');
    return r.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch(r.last.t);
  }

  /// Time from the first ring to your first reaction (snooze / off).
  Duration? get reaction {
    final ring = firstRingAt;
    if (ring == null) return null;
    for (final e in events) {
      if (e.type != 'ring' && e.t >= ring.millisecondsSinceEpoch) {
        return Duration(milliseconds: e.t - ring.millisecondsSinceEpoch);
      }
    }
    return null;
  }

  /// Single: snoozed at all. Series: snoozed, or a later alarm of the run rang.
  bool get sleptThrough => snoozes > 0 || extraRings > 0;

  /// Woke on the first ring and turned it off.
  bool get clean => !sleptThrough && wokeAt != null;

  bool get fast => (reaction?.inMilliseconds ?? 1 << 30) < kFastMs;

  int get score {
    if (wokeAt == null) return 0;
    if (clean) return kCleanWake + (fast ? kFastBonus : 0);
    return math.max(0, kLateWake - kSnoozePenalty * snoozes - kExtraRingPenalty * extraRings);
  }
}

class DayStats {
  final DateTime date; // midnight
  final List<Session> sessions;
  DayStats(this.date, this.sessions);

  int get rings => sessions.fold(0, (s, x) => s + x.rings);
  int get snoozes => sessions.fold(0, (s, x) => s + x.snoozes);
  int get extraRings => sessions.fold(0, (s, x) => s + x.extraRings);
  int get sleptThrough => sessions.where((s) => s.sleptThrough).length;
  int get cleanWakes => sessions.where((s) => s.clean).length;
  bool get clean => sessions.isNotEmpty && sessions.every((s) => s.clean);
  int get score => sessions.fold(0, (s, x) => s + x.score);

  /// When you got up: turn-off of the day's first session.
  DateTime? get wokeAt => sessions.isEmpty ? null : sessions.first.wokeAt;
}

class Achievement {
  final String id, title, hint;
  final bool unlocked;
  const Achievement(this.id, this.title, this.hint, this.unlocked);
}

class Stats {
  final List<Session> sessions;
  final List<DayStats> days; // oldest first, only days with alarms
  final DateTime now;

  Stats._(this.sessions, this.days, this.now);

  factory Stats.fromEvents(List<RingEvent> events, {DateTime? now}) {
    final byKey = <String, List<RingEvent>>{};
    for (final e in events) {
      byKey.putIfAbsent('${e.groupId}@${e.run}', () => []).add(e);
    }
    final sessions = byKey.values.map((evs) {
      evs.sort((a, b) => a.t.compareTo(b.t));
      final first = evs.first;
      return Session(first.groupId, DateTime.fromMillisecondsSinceEpoch(first.run), first.single, evs);
    }).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final byDay = <DateTime, List<Session>>{};
    for (final s in sessions) {
      byDay.putIfAbsent(dayOf(s.start), () => []).add(s);
    }
    final days = byDay.entries.map((e) => DayStats(e.key, e.value)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return Stats._(sessions, days, now ?? DateTime.now());
  }

  static DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  bool get isEmpty => sessions.isEmpty;

  DayStats? day(DateTime d) {
    final k = dayOf(d);
    for (final x in days) {
      if (x.date == k) return x;
    }
    return null;
  }

  int get totalXp => days.fold(0, (s, d) => s + d.score);
  int get level => math.sqrt(totalXp / 100).floor();
  int xpForLevel(int l) => l * l * 100;

  /// 0..1 progress from the current level to the next.
  double get levelProgress {
    final lo = xpForLevel(level), hi = xpForLevel(level + 1);
    return ((totalXp - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  /// Clean days in a row, newest backwards. Days without alarms don't break it.
  int get streak {
    var n = 0;
    for (final d in days.reversed) {
      if (!d.clean) break;
      n++;
    }
    return n;
  }

  int get bestStreak {
    var best = 0, cur = 0;
    for (final d in days) {
      cur = d.clean ? cur + 1 : 0;
      best = math.max(best, cur);
    }
    return best;
  }

  /// Stats for the last [n] calendar days (oldest first), empty days included as null.
  List<(DateTime, DayStats?)> lastDays(int n) {
    final today = dayOf(now);
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final d = DateTime(today.year, today.month, today.day - i);
          return (d, day(d));
        }(),
    ];
  }

  List<Achievement> get badges {
    final best = bestStreak;
    var comeback = false;
    for (var i = 1; i < days.length; i++) {
      if (days[i].clean && !days[i - 1].clean) comeback = true;
    }
    return [
      Achievement('first_ring', 'First Ring', 'Wake up on the first ring', sessions.any((s) => s.clean)),
      Achievement('lightning', 'Lightning', 'Turn an alarm off within 10 s',
          sessions.any((s) => s.clean && (s.reaction?.inSeconds ?? 99) < 10)),
      Achievement('early_bird', 'Early Bird', 'Get up before 6:00 on the first ring',
          sessions.any((s) => s.clean && s.wokeAt!.hour < 6)),
      Achievement('comeback', 'Comeback', 'A clean morning right after a sleepy one', comeback),
      Achievement('week', 'No-Snooze Week', '7 clean days in a row', best >= 7),
      Achievement('iron', 'Iron Will', '30 clean days in a row', best >= 30),
    ];
  }
}
