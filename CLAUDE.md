# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Android alarm clock (alarms, interval alarms, timer, stopwatch) built with Flutter UI + native Kotlin. Only Android is a real target; the other platform folders are Flutter scaffolding. Must work on **Android 5 (API 21) → 15** — every new platform API call needs a `Build.VERSION.SDK_INT` guard (see `missingPermissions()` in `MainActivity.kt` for the pattern).

## Commands

```bash
flutter pub get
flutter run                      # or --release
flutter build apk --debug        # then: adb install -r build/app/outputs/flutter-apk/app-debug.apk
flutter analyze                  # lints: flutter_lints via analysis_options.yaml
flutter test                     # only test: test/widget_test.dart (smoke test)
flutter test test/widget_test.dart --plain-name "App starts with the tab bar"
```

Kotlin changes need a full rebuild/reinstall — hot reload only applies Dart. Release builds use R8 minify + resource shrinking (`android/app/proguard-rules.pro`), signed with the debug key.

## Architecture

**Native owns all state that must survive the app being closed.** Alarms, timer, stopwatch, snoozes, ringtone, and button prefs are stored and scheduled in Kotlin (SharedPreferences/JSON). Dart is a UI layer that reads/writes through one MethodChannel; it never schedules anything itself. Only theme/accent settings live in Dart (`shared_preferences` + `provider` in `theme_provider.dart`).

- **Channel** `com.example.ak47clk/alarm`: all Dart→native calls are handled in the big `when` in `MainActivity.configureFlutterEngine`. Adding a feature usually means a new case there + a store method. Native→Dart calls: `clockChanged` (timer/stopwatch changed from a notification button; handled in `clock_widgets.dart`) and `openTab`.
- **Alarm model** (`AlarmStore.kt`): a *Group* (single alarm, or interval series from→to every N min, with `days` bitmask, `enabled`, `skipUntil`) containing *Alarms*, each with a unique id ≥ 100_000. The alarm id is the `PendingIntent` request code, so rescheduling with the same id replaces the old trigger. Snoozes use request code `-alarmId`. Reserved ids: `TIMER_ID = 99_000`, `TEST_ID = 98_500`; legacy alarms used `hour*100+minute` (migration in `AlarmStore.migrateIfNeeded`). Don't collide with these ranges.
- **Scheduling** (`AlarmScheduler.kt`): `setAlarmClock` when exact alarms are allowed, else `setAndAllowWhileIdle`. Repeat days apply to the day an interval run *starts* (an 11 PM–1 AM Friday run rings 1 AM Saturday). `rescheduleAll` restores alarms, snoozes, timer and stopwatch — called from `BootReceiver` (boot, app update, time/timezone change).
- **Ring path**: `AlarmReceiver` → `AlarmService` (foreground service: tone/vibration/notification, full-screen intent) → `AlarmActivity` (native, non-Flutter ring screen over the lock screen; swipe up = off, drag down = snooze; optional looping video with 4 s fallback to tone; hardware button actions from `ButtonPrefs`). Timer expiry and the Settings "Test alarm" go through the same path using the reserved ids.
- **Timer/stopwatch notifications**: `ClockNotif.kt` builds them, `ClockActionReceiver.kt` handles their buttons, then calls `MainActivity.notifyClockChanged()` so the Flutter UI reloads.
- **Permissions**: no popups on launch; `missingPermissions` returns keys shown as tappable banners on the Alarm page, `openPermission(key)` opens the right settings screen. MIUI lock-screen permission handling is in `MiuiPermissions.kt`.

- **Stats** (4th tab): `RingLog.kt` appends one JSON line per `ring` / `snooze` / `off` to `filesDir/ring_log.jsonl` (timer/test never logged), keyed by group id + `run` (start of that run/morning). Hooks live in `AlarmReceiver` and `AlarmActivity`. Dart reads it via `getRingLog` and `lib/stats/stats_engine.dart` (pure, unit-tested) builds sessions → days → score/XP/streak/badges. "Slept through" = single alarm snoozed, or interval run that snoozed / had a later alarm ring. A series counts as woken on the first ring only if you turn the group off in the app before its next alarm (by design: no stop-series control on the ring screen). No negative/"shame" badges.

`MainActivity.kt.temp` is a stray backup file, not compiled.

## Future ideas (not built yet)

- Google login + cloud sync (e.g. Firebase) for the stats history; for now history stays on the phone and moves via Android Auto Backup.
- Leaderboards / friend challenges built on the same session → day → score model.
