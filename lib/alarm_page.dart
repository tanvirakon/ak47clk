// lib/alarm_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({Key? key}) : super(key: key);

  @override
  _AlarmPageState createState() => _AlarmPageState();
}

class AlarmGroup {
  final String title;
  final List<Map<String, dynamic>> alarms;
  bool isExpanded;

  AlarmGroup({
    required this.title,
    required this.alarms,
    this.isExpanded = false,
  });
}

class _AlarmPageState extends State<AlarmPage> {
  static const platform = MethodChannel('com.example.ak47clk/alarm');

  TimeOfDay _fromTime = TimeOfDay.now();
  TimeOfDay _toTime = TimeOfDay.now();
  int _intervalMinutes = 10;
  List<Map<String, dynamic>> _alarms = [];
  List<AlarmGroup> _alarmGroups = [];

  // Map to track which interval alarms belong to which group
  Map<String, String> _alarmToGroupMap = {};

  @override
  void initState() {
    super.initState();
    _loadAlarms();

    // Initialize end time to be 1 hour after start time
    final now = TimeOfDay.now();
    _fromTime = now;
    _toTime = TimeOfDay(hour: (now.hour + 1) % 24, minute: now.minute);
  }

  // Format time to 12-hour format
  String _formatTime(int hour, int minute) {
    final now = DateTime.now();
    final dateTime = DateTime(now.year, now.month, now.day, hour, minute);
    return DateFormat('h:mm a').format(dateTime); // 12-hour format with am/pm
  }

  Future<void> _loadAlarms() async {
    try {
      final List<dynamic> alarms = await platform.invokeMethod('getAlarms');
      setState(() {
        // Convert raw alarms to our structured format
        _alarms =
            alarms
                .map((alarm) {
                  final parts = alarm.toString().split(':');
                  if (parts.length == 2) {
                    final hour = int.parse(parts[0]);
                    final minute = int.parse(parts[1]);
                    return {
                      'rawTime': alarm,
                      'formattedTime': _formatTime(hour, minute),
                      'hour': hour,
                      'minute': minute,
                      'groupId':
                          _alarmToGroupMap[alarm] ??
                          'single', // Default to 'single' if not in a group
                    };
                  }
                  return {
                    'rawTime': alarm,
                    'formattedTime': alarm,
                    'groupId': 'single',
                  };
                })
                .toList()
                .cast<Map<String, dynamic>>();

        // Organize alarms into groups
        _organizeAlarmGroups();
      });
    } on PlatformException catch (e) {
      print("Failed to load alarms: '${e.message}'.");
    } on MissingPluginException catch (e) {
      print("Method channel not implemented: ${e.message}");
      setState(() {
        _alarms = [];
        _alarmGroups = [];
      });
    }
  }

  // Organize alarms into their respective groups
  void _organizeAlarmGroups() {
    // Create a list to store current expanded states
    Map<String, bool> expandedStates = {};

    // Save current expanded states before rebuilding groups
    for (var group in _alarmGroups) {
      expandedStates[group.title] = group.isExpanded;
    }

    // Reset the groups
    _alarmGroups = [];

    // Group alarms by their groupId
    Map<String, List<Map<String, dynamic>>> groupedAlarms = {};
    Map<String, Map<String, dynamic>> groupInfo = {};

    // Process all alarms
    for (var alarm in _alarms) {
      final groupId = alarm['groupId'] ?? 'single';

      // Initialize group if first time seeing it
      if (!groupedAlarms.containsKey(groupId)) {
        groupedAlarms[groupId] = [];
      }

      // Add alarm to its group
      groupedAlarms[groupId]?.add(alarm);

      // Extract group metadata if it's not a single alarm
      if (groupId != 'single') {
        try {
          // Try to parse the group ID to extract metadata
          final parts = groupId.split('-');
          if (parts.length == 3) {
            final fromTimeParts = parts[0].split(':');
            final toTimeParts = parts[1].split(':');
            final interval = parts[2];

            final fromHour = int.parse(fromTimeParts[0]);
            final fromMinute = int.parse(fromTimeParts[1]);
            final toHour = int.parse(toTimeParts[0]);
            final toMinute = int.parse(toTimeParts[1]);

            final fromFormatted = _formatTime(fromHour, fromMinute);
            final toFormatted = _formatTime(toHour, toMinute);

            groupInfo[groupId] = {
              'title': "$fromFormatted to $toFormatted", // Simplified title
              'fromTime': fromFormatted,
              'toTime': toFormatted,
              'interval': interval,
            };
          }
        } catch (e) {
          print("Error parsing group ID: $e");
        }
      }
    }

    // Create single alarm group if any exist
    if (groupedAlarms.containsKey('single')) {
      final title = "Individual Alarms";
      _alarmGroups.add(
        AlarmGroup(
          title: title,
          alarms: groupedAlarms['single'] ?? [],
          isExpanded:
              expandedStates[title] ??
              true, // Use saved state or default to true
        ),
      );
    }

    // Add all interval alarm groups
    groupedAlarms.forEach((groupId, alarms) {
      if (groupId != 'single' && alarms.isNotEmpty) {
        final info = groupInfo[groupId];
        final title = info?['title'] ?? "Interval Alarms";

        _alarmGroups.add(
          AlarmGroup(
            title: title,
            alarms: alarms,
            isExpanded:
                expandedStates[title] ??
                false, // Use saved state or default to false
          ),
        );
      }
    });
  }

  // Delete all alarms in a group
  Future<void> _deleteAlarmGroup(AlarmGroup group) async {
    try {
      for (var alarm in group.alarms) {
        await platform.invokeMethod('deleteAlarm', {
          'hour': alarm['hour'],
          'minute': alarm['minute'],
        });

        // Remove from tracking map
        _alarmToGroupMap.remove(alarm['rawTime']);
      }

      // Update UI
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${group.alarms.length} alarms deleted")),
      );

      _loadAlarms();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete alarm group: $e")),
      );
    }
  }

  Future<void> _deleteAlarm(Map<String, dynamic> alarm) async {
    try {
      await platform.invokeMethod('deleteAlarm', {
        'hour': alarm['hour'],
        'minute': alarm['minute'],
      });
      _loadAlarms();
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete alarm: '${e.message}'")),
      );
    } on MissingPluginException catch (e) {
      print("Method channel not implemented: ${e.message}");
    }
  }

  Future<void> _setIntervalAlarms() async {
    try {
      final fromFormatted = _formatTime(_fromTime.hour, _fromTime.minute);
      final toFormatted = _formatTime(_toTime.hour, _toTime.minute);

      // Create a unique group ID for this interval set
      final groupId =
          "${_fromTime.hour}:${_fromTime.minute}-${_toTime.hour}:${_toTime.minute}-$_intervalMinutes";
      final groupTitle =
          "From $fromFormatted to $toFormatted (every $_intervalMinutes min)";

      await platform.invokeMethod('setIntervalAlarms', {
        'fromHour': _fromTime.hour,
        'fromMinute': _fromTime.minute,
        'toHour': _toTime.hour,
        'toMinute': _toTime.minute,
        'intervalMinutes': _intervalMinutes,
      });

      // Calculate what times should be in this group (for tracking)
      List<String> expectedAlarms = [];
      int startMinutes = (_fromTime.hour * 60) + _fromTime.minute;
      int endMinutes = (_toTime.hour * 60) + _toTime.minute;

      for (
        int currentMinutes = startMinutes;
        currentMinutes <= endMinutes;
        currentMinutes += _intervalMinutes
      ) {
        int hour = currentMinutes ~/ 60;
        int minute = currentMinutes % 60;
        expectedAlarms.add("$hour:$minute");

        // Map this alarm to the group
        _alarmToGroupMap["$hour:$minute"] = groupId;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Interval alarms set from $fromFormatted to $toFormatted every $_intervalMinutes minutes',
          ),
        ),
      );

      // Refresh alarms list
      _loadAlarms();
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to set interval alarms: '${e.message}'"),
        ),
      );
    } on MissingPluginException catch (e) {
      print("Method channel not implemented: ${e.message}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Setting interval alarms - please check your device alarms",
          ),
        ),
      );
    }
  }

  Future<void> _selectFromTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _fromTime,
    );
    if (picked != null && picked != _fromTime) {
      setState(() {
        _fromTime = picked;
      });
    }
  }

  Future<void> _selectToTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _toTime,
    );
    if (picked != null && picked != _toTime) {
      setState(() {
        _toTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Format times for display
    final formattedFromTime = _formatTime(_fromTime.hour, _fromTime.minute);
    final formattedToTime = _formatTime(_toTime.hour, _toTime.minute);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ak47clk'),
        actions: [
          IconButton(
            icon: Icon(
              themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              themeProvider.toggleTheme(!themeProvider.isDarkMode);
            },
            tooltip: themeProvider.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4.0,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const Text('From'),
                              const SizedBox(height: 8),
                              Text(
                                formattedFromTime,
                                style: const TextStyle(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () => _selectFromTime(context),
                                child: const Text('Select Start'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              const Text('To'),
                              const SizedBox(height: 8),
                              Text(
                                formattedToTime,
                                style: const TextStyle(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () => _selectToTime(context),
                                child: const Text('Select End'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Column(
                      children: [
                        const Text('Interval (minutes)'),
                        const SizedBox(height: 8),
                        DropdownButton<int>(
                          value: _intervalMinutes,
                          items:
                              [2, 5, 8, 10].map((int value) {
                                return DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value minutes'),
                                );
                              }).toList(),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _intervalMinutes = newValue;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _setIntervalAlarms,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Set Interval Alarms'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildAlarmsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmsList() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Alarms',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(
            child:
                _alarmGroups.isEmpty
                    ? const Center(child: Text('No alarms set'))
                    : ListView.builder(
                      itemCount: _alarmGroups.length,
                      itemBuilder: (context, groupIndex) {
                        final group = _alarmGroups[groupIndex];
                        return Card(
                          margin: EdgeInsets.only(bottom: 8),
                          child: Column(
                            children: [
                              // Group header
                              ListTile(
                                title: Text(
                                  group.title,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Delete button (red)
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _deleteAlarmGroup(group),
                                    ),
                                    // Expand/collapse button
                                    IconButton(
                                      icon: Icon(
                                        group.isExpanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          group.isExpanded = !group.isExpanded;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() {
                                    group.isExpanded = !group.isExpanded;
                                  });
                                },
                              ),

                              // Expandable alarm list
                              if (group.isExpanded)
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount: group.alarms.length,
                                  itemBuilder: (context, alarmIndex) {
                                    final alarm = group.alarms[alarmIndex];
                                    return ListTile(
                                      contentPadding: EdgeInsets.only(
                                        left: 32,
                                        right: 16,
                                      ),
                                      title: Text(
                                        alarm['formattedTime'],
                                        style: TextStyle(fontSize: 14),
                                      ),
                                      trailing: IconButton(
                                        icon: Icon(Icons.delete, size: 20),
                                        onPressed: () => _deleteAlarm(alarm),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
