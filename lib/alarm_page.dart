// lib/alarm_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';

class AlarmPage extends StatefulWidget {
  const AlarmPage({Key? key}) : super(key: key);

  @override
  _AlarmPageState createState() => _AlarmPageState();
}

class AlarmGroup {
  final String title;
  final String groupId;
  final List<Map<String, dynamic>> alarms;
  bool isExpanded;
  bool isEnabled;

  AlarmGroup({
    required this.title,
    required this.groupId,
    required this.alarms,
    this.isExpanded = false,
    this.isEnabled = true,
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
    _loadAlarmGroupMappings();
    _loadAlarms();

    // Initialize end time to be 1 hour after start time
    final now = TimeOfDay.now();
    _fromTime = now;
    _toTime = TimeOfDay(hour: (now.hour + 1) % 24, minute: now.minute);
  }
  
  // Load alarm group mappings from SharedPreferences
  Future<void> _loadAlarmGroupMappings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingsString = prefs.getString('alarm_group_mappings');
      if (mappingsString != null && mappingsString.isNotEmpty) {
        // Parse the string format: "hour:minute|groupId,hour:minute|groupId,..."
        // Using | as separator between time and groupId to avoid conflicts with : in groupId
        final Map<String, String> mappings = {};
        final entries = mappingsString.split(',');
        for (var entry in entries) {
          final parts = entry.split('|');
          if (parts.length == 2) {
            final timeKey = parts[0]; // "hour:minute"
            final groupId = parts[1]; // groupId
            mappings[timeKey] = groupId;
          }
        }
        _alarmToGroupMap = mappings;
      }
    } catch (e) {
      print("Error loading alarm group mappings: $e");
    }
  }
  
  // Save alarm group mappings to SharedPreferences
  Future<void> _saveAlarmGroupMappings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Convert map to a simple string format: "hour:minute|groupId,hour:minute|groupId,..."
      // Using | as separator to avoid conflicts with : in time format
      final mappingsString = _alarmToGroupMap.entries
          .map((e) => "${e.key}|${e.value}")
          .join(',');
      await prefs.setString('alarm_group_mappings', mappingsString);
    } catch (e) {
      print("Error saving alarm group mappings: $e");
    }
  }
  
  // Toggle alarm group on/off
  Future<void> _toggleAlarmGroup(AlarmGroup group) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newState = !group.isEnabled;
      
      setState(() {
        group.isEnabled = newState;
      });
      
      // Save the enabled state
      await prefs.setBool('alarm_group_enabled_${group.groupId}', newState);
      
      // Save the updated groups (to persist the group structure)
      await _saveAlarmGroups();
      
      if (newState) {
        // Enable: Recreate all alarms in the group
        for (var alarm in group.alarms) {
          await platform.invokeMethod('setAlarm', {
            'hour': alarm['hour'],
            'minute': alarm['minute'],
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${group.title} enabled")),
        );
      } else {
        // Disable: Delete all alarms in the group (but keep them in memory)
        for (var alarm in group.alarms) {
          await platform.invokeMethod('deleteAlarm', {
            'hour': alarm['hour'],
            'minute': alarm['minute'],
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${group.title} disabled")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to toggle alarm group: $e")),
      );
      // Revert on error
      setState(() {
        group.isEnabled = !group.isEnabled;
      });
    }
  }

  // Format time to 12-hour format
  String _formatTime(int hour, int minute) {
    final now = DateTime.now();
    final dateTime = DateTime(now.year, now.month, now.day, hour, minute);
    return DateFormat('h:mm a').format(dateTime); // 12-hour format with am/pm
  }

  Future<void> _loadAlarms() async {
    try {
      final List<dynamic> activeAlarms = await platform.invokeMethod('getAlarms');
      
      // Convert active alarms to our structured format
      final activeAlarmsList =
          activeAlarms
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

      // Load stored alarm groups (includes disabled groups)
      await _loadStoredAlarmGroups(activeAlarmsList);
      
      setState(() {});
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
  
  // Load stored alarm groups from SharedPreferences
  Future<void> _loadStoredAlarmGroups(List<Map<String, dynamic>> activeAlarms) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get all stored group IDs
    final storedGroupsJson = prefs.getString('stored_alarm_groups');
    if (storedGroupsJson == null || storedGroupsJson.isEmpty) {
      // No stored groups, organize from active alarms only
      _alarms = activeAlarms;
      await _organizeAlarmGroups();
      // Save the organized groups for next time
      await _saveAlarmGroups();
      return;
    }
    
    // Parse stored groups: "groupId|alarm1,alarm2,alarm3;groupId2|alarm1,alarm2;..."
    final Map<String, List<Map<String, dynamic>>> storedGroups = {};
    final groupStrings = storedGroupsJson.split(';');
    
    for (var groupString in groupStrings) {
      if (groupString.isEmpty) continue;
      final parts = groupString.split('|');
      if (parts.length == 2) {
        final groupId = parts[0];
        final alarmsString = parts[1];
        if (alarmsString.isNotEmpty) {
          final alarmTimes = alarmsString.split(',');
          final alarms = alarmTimes.map((time) {
            final timeParts = time.split(':');
            if (timeParts.length == 2) {
              final hour = int.parse(timeParts[0]);
              final minute = int.parse(timeParts[1]);
              return {
                'rawTime': time,
                'formattedTime': _formatTime(hour, minute),
                'hour': hour,
                'minute': minute,
                'groupId': groupId,
              };
            }
            return null;
          }).where((a) => a != null).cast<Map<String, dynamic>>().toList();
          storedGroups[groupId] = alarms;
        }
      }
    }
    
    // Merge stored groups with active alarms
    // Use stored groups as base, but mark which alarms are active
    final allAlarms = <String, Map<String, dynamic>>{};
    
    // Add all stored alarms
    for (var group in storedGroups.values) {
      for (var alarm in group) {
        allAlarms[alarm['rawTime']] = alarm;
      }
    }
    
    // Update with active alarm status
    for (var activeAlarm in activeAlarms) {
      allAlarms[activeAlarm['rawTime']] = activeAlarm;
    }
    
    _alarms = allAlarms.values.toList();
    await _organizeAlarmGroups();
  }
  
  // Save alarm groups to SharedPreferences
  Future<void> _saveAlarmGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save groups in format: "groupId|alarm1,alarm2,alarm3;groupId2|alarm1,alarm2;..."
      final List<String> groupStrings = [];
      
      for (var group in _alarmGroups) {
        final alarmTimes = group.alarms
            .map((a) => a['rawTime'].toString())
            .join(',');
        groupStrings.add("${group.groupId}|$alarmTimes");
      }
      
      await prefs.setString('stored_alarm_groups', groupStrings.join(';'));
    } catch (e) {
      print("Error saving alarm groups: $e");
    }
  }

  // Organize alarms into their respective groups
  Future<void> _organizeAlarmGroups() async {
    // Create a list to store current expanded states and enabled states
    Map<String, bool> expandedStates = {};
    Map<String, bool> enabledStates = {};

    // Save current states before rebuilding groups
    for (var group in _alarmGroups) {
      expandedStates[group.groupId] = group.isExpanded;
      enabledStates[group.groupId] = group.isEnabled;
    }
    
    // Load enabled states from SharedPreferences
    final prefs = await SharedPreferences.getInstance();

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
      final groupId = 'single';
      final title = "Individual Alarms";
      _alarmGroups.add(
        AlarmGroup(
          title: title,
          groupId: groupId,
          alarms: groupedAlarms['single'] ?? [],
          isExpanded: expandedStates[groupId] ?? true,
          isEnabled: prefs.getBool('alarm_group_enabled_$groupId') ?? true,
        ),
      );
    }

    // Add all interval alarm groups
    groupedAlarms.forEach((groupId, alarms) {
      if (groupId != 'single' && alarms.isNotEmpty) {
        final info = groupInfo[groupId];
        final title = info?['title'] ?? "Interval Alarms";
        final isEnabled = prefs.getBool('alarm_group_enabled_$groupId') ?? true;

        _alarmGroups.add(
          AlarmGroup(
            title: title,
            groupId: groupId,
            alarms: alarms,
            isExpanded: expandedStates[groupId] ?? false,
            isEnabled: isEnabled,
          ),
        );
        
        // If group is disabled, make sure alarms are deleted from AlarmManager
        if (!isEnabled) {
          // Delete alarms in disabled groups (they might have been restored on boot)
          for (var alarm in alarms) {
            platform.invokeMethod('deleteAlarm', {
              'hour': alarm['hour'],
              'minute': alarm['minute'],
            }).catchError((e) {
              print("Error deleting disabled alarm: $e");
            });
          }
        }
      }
    });
    
    // Also check individual alarms group
    if (groupedAlarms.containsKey('single')) {
      final isEnabled = prefs.getBool('alarm_group_enabled_single') ?? true;
      if (!isEnabled) {
        // Delete individual alarms if group is disabled
        for (var alarm in groupedAlarms['single'] ?? []) {
          platform.invokeMethod('deleteAlarm', {
            'hour': alarm['hour'],
            'minute': alarm['minute'],
          }).catchError((e) {
            print("Error deleting disabled alarm: $e");
          });
        }
      }
    }
    
    // Save the organized groups
    await _saveAlarmGroups();
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
      
      // Save the updated group mappings
      await _saveAlarmGroupMappings();
      
      // Remove group from stored groups
      _alarmGroups.removeWhere((g) => g.groupId == group.groupId);
      await _saveAlarmGroups();

      // Update UI
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${group.alarms.length} alarms deleted")),
      );

      setState(() {});
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
      
      // Remove from tracking map
      _alarmToGroupMap.remove(alarm['rawTime']);
      await _saveAlarmGroupMappings();
      
      // Remove from stored groups and save
      for (var group in _alarmGroups) {
        group.alarms.removeWhere((a) => a['rawTime'] == alarm['rawTime']);
      }
      _alarmGroups.removeWhere((group) => group.alarms.isEmpty);
      await _saveAlarmGroups();
      
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
      
      // Save the group mappings
      await _saveAlarmGroupMappings();
      
      // Refresh alarms list to update groups
      await _loadAlarms();
      
      // Save the updated groups
      await _saveAlarmGroups();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Interval alarms set from $fromFormatted to $toFormatted every $_intervalMinutes minutes',
          ),
        ),
      );
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
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: group.isEnabled ? null : Colors.grey,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // On/Off Switch
                                    Switch(
                                      value: group.isEnabled,
                                      onChanged: (value) => _toggleAlarmGroup(group),
                                    ),
                                    const SizedBox(width: 8),
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
