import 'package:flutter_test/flutter_test.dart';
import 'package:ak47clk/stats/stats_engine.dart';

int at(int day, int h, int m, [int s = 0]) => DateTime(2026, 11, day, h, m, s).millisecondsSinceEpoch;

RingEvent ev(String type, int t, {int g = 1, required int run, bool single = true, bool snz = false}) =>
    RingEvent(t: t, type: type, alarmId: g * 10, groupId: g, run: run, single: single, fromSnooze: snz);

void main() {
  group('single alarm', () {
    test('off on first ring = clean, fast bonus', () {
      final run = at(1, 7, 0);
      final s = Stats.fromEvents([ev('ring', run, run: run), ev('off', run + 5000, run: run)]);
      final x = s.sessions.single;
      expect(x.clean, isTrue);
      expect(x.sleptThrough, isFalse);
      expect(x.score, kCleanWake + kFastBonus);
    });

    test('snoozed = slept through', () {
      final run = at(1, 7, 0);
      final s = Stats.fromEvents([
        ev('ring', run, run: run),
        ev('snooze', run + 60000, run: run),
        ev('ring', run + 6 * 60000, run: run, snz: true),
        ev('off', run + 6 * 60000 + 3000, run: run),
      ]);
      final x = s.sessions.single;
      expect(x.sleptThrough, isTrue);
      expect(x.snoozes, 1);
      expect(x.rings, 2);
      expect(x.score, kLateWake - kSnoozePenalty);
    });
  });

  group('interval series', () {
    test('one ring, off, nothing else rang = clean', () {
      final run = at(2, 6, 0);
      final s = Stats.fromEvents([
        ev('ring', run, run: run, single: false),
        ev('off', run + 20000, run: run, single: false),
      ]);
      expect(s.sessions.single.clean, isTrue);
    });

    test('off then next alarm rang = slept through', () {
      final run = at(2, 6, 0);
      final s = Stats.fromEvents([
        ev('ring', run, run: run, single: false),
        ev('off', run + 10000, run: run, single: false),
        ev('ring', run + 5 * 60000, run: run, single: false),
        ev('off', run + 5 * 60000 + 10000, run: run, single: false),
      ]);
      final x = s.sessions.single;
      expect(x.sleptThrough, isTrue);
      expect(x.extraRings, 1);
      expect(x.score, kLateWake - kExtraRingPenalty);
    });
  });

  test('streak, xp, days and badges', () {
    final events = <RingEvent>[];
    // Day 1 sleepy (snooze), days 2-4 clean.
    final r1 = at(1, 7, 0);
    events.addAll([ev('ring', r1, run: r1), ev('snooze', r1 + 1000, run: r1),
      ev('ring', r1 + 300000, run: r1, snz: true), ev('off', r1 + 301000, run: r1)]);
    for (final d in [2, 3, 4]) {
      final r = at(d, 5, 30);
      events.addAll([ev('ring', r, run: r), ev('off', r + 4000, run: r)]);
    }
    final s = Stats.fromEvents(events, now: DateTime(2026, 11, 4, 12));
    expect(s.days.length, 4);
    expect(s.streak, 3);
    expect(s.bestStreak, 3);
    expect(s.totalXp, (kLateWake - kSnoozePenalty) + 3 * (kCleanWake + kFastBonus));
    final unlocked = {for (final b in s.badges) if (b.unlocked) b.id};
    expect(unlocked, containsAll(['first_ring', 'lightning', 'early_bird', 'comeback']));
    expect(unlocked.contains('week'), isFalse);
    final last7 = s.lastDays(7);
    expect(last7.length, 7);
    expect(last7.last.$2?.clean, isTrue);
  });

  test('parses native json and skips broken entries', () {
    final list = RingEvent.listFromJson(
        '[{"t":5,"type":"ring","a":1,"g":2,"run":5,"single":false},{"bad":1}]');
    expect(list.length, 1);
    expect(list.first.single, isFalse);
  });
}
