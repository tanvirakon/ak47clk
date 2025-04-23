// lib/alarm_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:intl/intl.dart'; // Add this import for time formatting

class AlarmPage extends StatefulWidget {
  const AlarmPage({Key? key}) : super(key: key);

  @override
  _AlarmPageState createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  static const platform = MethodChannel('com.example.ak47clk/alarm');
  
  TimeOfDay _selectedTime = TimeOfDay.now();
  List<Map<String, dynamic>> _alarms = [];

  @override
  void initState() {
    super.initState();
    _loadAlarms();
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
        _alarms = alarms.map((alarm) {
          final parts = alarm.toString().split(':');
          if (parts.length == 2) {
            final hour = int.parse(parts[0]);
            final minute = int.parse(parts[1]);
            return {
              'rawTime': alarm,
              'formattedTime': _formatTime(hour, minute),
              'hour': hour,
              'minute': minute,
            };
          }
          return {'rawTime': alarm, 'formattedTime': alarm};
        }).toList().cast<Map<String, dynamic>>();
      });
    } on PlatformException catch (e) {
      print("Failed to load alarms: '${e.message}'.");
    } on MissingPluginException catch (e) {
      print("Method channel not implemented: ${e.message}");
      setState(() {
        _alarms = [];
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _setAlarm() async {
    try {
      final formattedTime = _formatTime(_selectedTime.hour, _selectedTime.minute);
      await platform.invokeMethod('setCustomAlarm', {
        'hour': _selectedTime.hour,
        'minute': _selectedTime.minute,
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alarm set for $formattedTime')),
      );
      
      // Refresh alarms list
      _loadAlarms();
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to set alarm: '${e.message}'")),
      );
    } on MissingPluginException catch (e) {
      print("Method channel not implemented: ${e.message}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Setting alarm - please check your device alarms")),
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

  @override
  Widget build(BuildContext context) {
    // Format selected time for display
    final formattedSelectedTime = _formatTime(_selectedTime.hour, _selectedTime.minute);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('AK47 Alarm Clock'),
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
                    Text(
                      'Selected Time: $formattedSelectedTime',
                      style: const TextStyle(fontSize: 18.0),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => _selectTime(context),
                      child: const Text('Select Time'),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _setAlarm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Set Alarm'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Current Alarms',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _alarms.isEmpty
                  ? const Center(child: Text('No alarms set'))
                  : ListView.builder(
                      itemCount: _alarms.length,
                      itemBuilder: (context, index) {
                        return Card(
                          child: ListTile(
                            title: Text(
                              _alarms[index]['formattedTime'],
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteAlarm(_alarms[index]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}