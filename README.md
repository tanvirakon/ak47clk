<!-- filepath: e:\code i write\ak47clk\README.md -->

# AK47 Alarm Clock

A customizable interval alarm clock app built with Flutter that allows you to set multiple alarms at regular intervals. Alarms ring reliably even when your phone is locked, in sleep mode, or when using other apps.

## Features

- **Interval Alarms**: Set a series of alarms between two time points at regular intervals
- **Flexible Intervals**: Choose from 2, 5, 8, or 10 minute intervals
- **Organized Interface**: Alarms are grouped by time range for easy management
- **Batch Delete**: Delete an entire group of interval alarms with one tap
- **Individual Control**: Expand alarm groups to manage individual alarms
- **Persistent Storage**: Alarms are saved and automatically restored when you restart the app
- **Reliable Notifications**: Full-screen alarm alerts that work even when:
  - Your device is locked
  - Phone is in sleep/Doze mode
  - You're using other apps (browsing, watching movies, etc.)
  - Alarms are set for extended periods (6+ hours ahead)
- **Redundant Scheduling**: Dual alarm system ensures alarms never get missed
- **Normal Volume Control**: Alarms ring at your system alarm volume level
- **Dark/Light Theme**: Support for both light and dark mode

## How It Works

1. **Set Interval Range**: Choose a start time and end time for your alarms
2. **Choose Interval**: Select how frequently alarms should trigger (2, 5, 8, or 10 minutes)
3. **View Alarms**: See your alarms in expandable groups organized by time range
4. **Manage Alarms**:
   - Delete entire groups with the red delete button
   - Expand groups to delete individual alarms
   - Alarms persist even after closing the app
5. **Dismiss Alarms**: When an alarm rings, tap the "Off" button to dismiss it
   - Other alarms in the series remain active and will ring as scheduled

## Technical Implementation

- **Platform**: Built with Flutter for cross-platform support
- **Native Integration**: Uses platform channels to communicate with native Android alarm APIs
- **Background Operation**:
  - Alarms work even when the app is closed or device is locked
  - Uses Android AlarmManager for reliable scheduling
  - Implements Foreground Service for launching alarms over other apps
- **Persistent Storage**: SharedPreferences for saving alarm state across app restarts
- **Redundant Scheduling**: Dual alarm system (exact + repeating) for maximum reliability
- **Battery Optimization**: Works around Android Doze mode restrictions
- **Permission Handling**: Requests necessary permissions (SYSTEM_ALERT_WINDOW, SCHEDULE_EXACT_ALARM, etc.)
- **Efficient UI**: Organized expandable UI for managing large numbers of alarms

## How Alarms Work Behind the Scenes

1. When you set interval alarms, the app creates multiple alarms at regular intervals
2. Each alarm is scheduled twice:
   - **Primary alarm**: Exact alarm that fires at precise time
   - **Backup alarm**: Repeating daily alarm for redundancy
3. When alarm time arrives:
   - Android triggers the BroadcastReceiver
   - A Foreground Service is started with high priority
   - The alarm activity is launched, playing sound and displaying the alarm screen
   - Notification is shown as backup visual indicator
4. When you dismiss an alarm, both primary and backup alarms are cancelled

## Getting Started

### Prerequisites

- Flutter SDK (latest version)
- Android Studio or VS Code with Flutter plugins
- An Android device or emulator (API 21+)
- Gradle 7.0+

### Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/tanvirakon/ak47clk.git
   cd ak47clk
   ```

2. Install dependencies:

   ```bash
   flutter pub get
   ```

3. Connect your Android device or start an emulator

4. Run the app:
   ```bash
   flutter run
   ```

### Important Permissions

When you first run the app, you'll be asked to grant:

- **SCHEDULE_EXACT_ALARM**: To schedule alarms at precise times
- **SYSTEM_ALERT_WINDOW**: To display alarms over other apps
- **WAKE_LOCK**: To wake your device when alarms trigger

Grant these permissions for the app to work properly.

## Troubleshooting

### Alarms not ringing?

1. Make sure you've granted all necessary permissions
2. Check that your phone's alarm volume is not muted
3. Ensure the app is not being killed by battery optimization
4. Restart the app and try again

### Alarms showing up as notifications but not launching?

- Grant the SYSTEM_ALERT_WINDOW permission in app settings
- Go to Settings > Apps > AK47 Clock > Permissions > Display over other apps > Allow

### Alarms not persisting after restart?

- This may indicate a storage issue; try reinstalling the app

## Project Structure

```
ak47clk/
├── lib/
│   ├── main.dart              # App entry point
│   ├── alarm_page.dart        # Main UI for setting and managing alarms
│   ├── theme_provider.dart    # Theme management (light/dark mode)
│   └── ...
├── android/
│   ├── app/src/main/
│   │   ├── AndroidManifest.xml
│   │   └── kotlin/com/example/ak47clk/
│   │       ├── MainActivity.kt       # Main Android activity & alarm setup
│   │       ├── AlarmReceiver.kt      # Broadcasts receiver for alarm triggers
│   │       ├── AlarmService.kt       # Foreground service for launching alarms
│   │       ├── AlarmActivity.kt      # Full-screen alarm display activity
│   │       └── BootReceiver.kt       # Restores alarms after device boot
│   └── ...
└── pubspec.yaml               # Flutter dependencies
```

## Dependencies

- `flutter_launcher_icons`: For custom app icon
- `provider`: State management
- `shared_preferences`: Local data persistence
- `intl`: Date/time formatting

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Flutter team for the excellent cross-platform framework
- Android documentation for AlarmManager and Foreground Services
- Community feedback for bug fixes and improvements

## Version History

### v1.0.0 (Current)

- Initial release
- Full interval alarm functionality
- Persistent alarm storage
- Reliable alarm ringing across all Android versions
- Dark/Light theme support
- Organized alarm management UI

---

**Note**: This app is optimized for Android. iOS support may be added in future versions.
