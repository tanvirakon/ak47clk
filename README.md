# ak47clk

A customizable interval alarm clock app built with Flutter that allows you to set multiple alarms at regular intervals.

## Features

- **Interval Alarms**: Set a series of alarms between two time points at regular intervals
- **Flexible Intervals**: Choose from 2, 5, 8, or 10 minute intervals
- **Organized Interface**: Alarms are grouped by time range for easy management
- **Batch Delete**: Delete an entire group of interval alarms with one tap
- **Individual Control**: Expand alarm groups to manage individual alarms
- **Reliable Notifications**: Full-screen alarm alerts that work even when your device is locked

## How It Works

1. **Set Interval Range**: Choose a start time and end time for your alarms
2. **Choose Interval**: Select how frequently alarms should trigger (2, 5, 8, or 10 minutes)
3. **Manage Easily**: View your alarms in expandable groups organized by time range
4. **Simple Dismissal**: When an alarm rings, just tap "Off" to dismiss (other alarms in the series remain active)

## Technical Implementation

- **Platform**: Built with Flutter for cross-platform support
- **Native Integration**: Uses platform channels to access native Android alarm APIs
- **Background Operation**: Alarms work even when the app is closed or device is locked
- **Efficient UI**: Organized expandable UI for managing large numbers of alarms

## Screenshots

[Screenshots would be placed here]

## Getting Started

### Prerequisites

- Flutter SDK
- Android Studio or VS Code with Flutter plugins
- An Android device or emulator

### Installation

1. Clone this repository
2. Run `flutter pub get` to install dependencies
3. Connect your device or start an emulator
4. Run `flutter run` to launch the app

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Flutter team for the excellent cross-platform framework
- Android alarm APIs for reliable alarm functionality
