# AK47 Alarm Clock

A clean, reliable clock app for Android built with Flutter + native Kotlin. Alarms, interval alarms, timer and stopwatch — all ring on the lock screen, survive reboots, and work with the app closed.

## Features

### Alarms
- **Single alarm**: one tap on **+**, pick a time on the wheel, done. Turns itself off after ringing (flip the switch to reuse it). Tap a card to edit.
- **Interval alarms**: a series of alarms between two times, every 2 / 5 / 8 / 10 min (2 min default). Ranges past midnight (e.g. 11 PM → 1 AM) work.
- **One list**, sorted by time. Switch groups on/off, expand to remove single times, swipe left to delete.
- **"Next alarm in …"** countdown at the top.

### Timer
- h / m / s wheels with a dial tick sound + haptic; quick presets 1 · 5 · 10 · 15 min.
- Draining ring with time left and end time; pause/resume, cancel, **+1:00**.
- Rings with the full alarm screen (“Time's up”); live countdown notification while running.

### Stopwatch
- Big digits with a sweeping dot; start/pause, lap, reset.
- Laps newest on top, fastest in green, slowest in red.
- Keeps counting with the app closed.

### Ringing
- Full-screen ring screen that shows **over the lock screen** (no unlock needed) — swipe up to turn OFF.
- Ringtone: any system **tone**, or a **video** (plays fullscreen with its audio, loops until OFF). Only one video is kept; picking a tone removes it.
- Follows your phone's **alarm volume**. Keeps ringing until you turn it off.

### App
- Bottom bar (icons only), **swipe between tabs**; settings gear stays fixed on every tab.
- Settings: dark / light mode (instant), alarm ringtone.
- Professional look in both light and dark mode; MIUI-style wheel time picker.

## Reliability

- Every alarm has a **unique ID** → two groups can share a time without clashing.
- Scheduled with `AlarmManager.setAlarmClock` (exempt from Doze, shows the ⏰ status icon).
- All alarms + timer stored natively, so they're **restored after reboot**, app update, or clock / timezone change — without opening the app.
- Video fallback: if a video can't start within 4 s, the tone rings so an alarm is never silent.
- Built for **Android 5 (API 21) → Android 15**, with handling for Android 12 exact alarms, Android 13 notification permission, Android 14 foreground-service / full-screen-intent rules, and MIUI lock-screen permissions.

## Getting Started

### Prerequisites
- Flutter SDK
- Android SDK command-line tools (Android Studio not required)
- An Android phone with USB debugging on (API 21+)

### Run
```bash
git clone https://github.com/tanvirakon/ak47clk.git
cd ak47clk
flutter pub get
flutter run            # or: flutter run --release (smoother)
```

Or build and install manually:
```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

> Native (Kotlin) changes need a full rebuild — hot reload only applies Dart changes.

### Permissions asked on first launch
- Exact alarms, notifications (Android 13+), full-screen alerts (Android 14+)
- Display over other apps, ignore battery optimization
- **MIUI / Xiaomi**: if a banner says the alarm can't show on the lock screen, tap it and allow *Show on Lock screen* and *Display pop-up windows while running in the background*.

## Troubleshooting

- **Alarm rings but screen doesn't show on lock screen** → allow the MIUI permissions above / full-screen alerts.
- **No sound** → check the phone's alarm volume.
- **Alarm late or missing** → set battery saver for the app to *No restrictions*.

## Project Structure

```
lib/
├── main.dart               # App entry, light/dark themes
├── home_shell.dart         # Bottom bar + swipeable tabs + settings gear
├── alarm_page.dart         # Alarm list, add/edit bubble card
├── timer_page.dart         # Countdown timer
├── stopwatch_page.dart     # Stopwatch + laps
├── clock_widgets.dart      # Shared round buttons, ring painter
├── wheel_time_picker.dart  # Wheel picker + dial tick
├── settings_page.dart      # Dark mode, ringtone (tone / video)
└── theme_provider.dart

android/app/src/main/kotlin/com/example/ak47clk/
├── MainActivity.kt         # Method channel, permissions, pickers
├── AlarmStore.kt           # Alarm storage (JSON), unique IDs, migration
├── AlarmScheduler.kt       # AlarmManager scheduling / reschedule all
├── TimerStore.kt           # Timer state + countdown notification
├── AlarmReceiver.kt        # Alarm fired → start service
├── AlarmService.kt         # Foreground service: tone, vibration, notification
├── AlarmActivity.kt        # Full-screen ring screen (lock screen, video)
├── BootReceiver.kt         # Restore after reboot / update / time change
├── RingtoneStore.kt        # Tone / video ringtone storage
├── TickSound.kt            # Wheel tick sound
└── MiuiPermissions.kt      # MIUI lock-screen permission check
```

## Dependencies

- `provider` — theme state
- `shared_preferences` — settings, stopwatch state
- `intl` — time formatting
- `flutter_launcher_icons` — app icon

## License

MIT — see LICENSE.
