// lib/wheel_time_picker.dart
import 'package:flutter/material.dart';

/// Bottom-sheet wheel time picker (AM/PM | hour | minute).
Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
  String title = 'Select time',
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WheelTimePickerSheet(initial: initialTime, title: title),
  );
}

class _WheelTimePickerSheet extends StatefulWidget {
  final TimeOfDay initial;
  final String title;
  const _WheelTimePickerSheet({required this.initial, required this.title});

  @override
  State<_WheelTimePickerSheet> createState() => _WheelTimePickerSheetState();
}

class _WheelTimePickerSheetState extends State<_WheelTimePickerSheet> {
  static const double _itemExtent = 64;

  late int _hour12; // 1..12
  late int _minute; // 0..59
  late bool _isPm;

  late final FixedExtentScrollController _ampmCtrl;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  @override
  void initState() {
    super.initState();
    final h = widget.initial.hour;
    _isPm = h >= 12;
    _hour12 = h % 12 == 0 ? 12 : h % 12;
    _minute = widget.initial.minute;

    _ampmCtrl = FixedExtentScrollController(initialItem: _isPm ? 1 : 0);
    // Large offset so looping wheels can scroll both ways from start.
    _hourCtrl = FixedExtentScrollController(initialItem: 1200 + (_hour12 - 1));
    _minuteCtrl = FixedExtentScrollController(initialItem: 6000 + _minute);
  }

  @override
  void dispose() {
    _ampmCtrl.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  TimeOfDay get _value {
    final h24 = (_hour12 % 12) + (_isPm ? 12 : 0);
    return TimeOfDay(hour: h24, minute: _minute);
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF242424) : Colors.white;
    final fg = isDark ? Colors.white : Colors.black87;
    final dim = isDark ? Colors.white38 : Colors.black38;
    final btnBg = isDark ? const Color(0xFF363636) : const Color(0xFFEFEFEF);
    final divider = isDark ? Colors.white10 : Colors.black12;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: TextStyle(color: dim, fontSize: 14)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${_two(_hour12)}:${_two(_minute)}',
                  style: TextStyle(
                    color: fg,
                    fontSize: 40,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isPm ? 'pm' : 'am',
                  style: TextStyle(color: fg, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: _itemExtent * 3,
              child: Row(
                children: [
                  Expanded(
                    child: _wheel(
                      controller: _ampmCtrl,
                      count: 2,
                      looping: false,
                      label: (i) => i == 0 ? 'AM' : 'PM',
                      isSelected: (i) => (i == 1) == _isPm,
                      onChanged: (i) => setState(() => _isPm = i == 1),
                      fg: fg,
                      dim: dim,
                      selectedSize: 30,
                    ),
                  ),
                  VerticalDivider(color: divider, width: 1),
                  Expanded(
                    child: _wheel(
                      controller: _hourCtrl,
                      count: 12,
                      looping: true,
                      label: (i) => _two(i + 1),
                      isSelected: (i) => i + 1 == _hour12,
                      onChanged: (i) => setState(() => _hour12 = i + 1),
                      fg: fg,
                      dim: dim,
                    ),
                  ),
                  VerticalDivider(color: divider, width: 1),
                  Expanded(
                    child: _wheel(
                      controller: _minuteCtrl,
                      count: 60,
                      looping: true,
                      label: _two,
                      isSelected: (i) => i == _minute,
                      onChanged: (i) => setState(() => _minute = i),
                      fg: fg,
                      dim: dim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _pillButton(
                    'Cancel',
                    btnBg,
                    fg,
                    () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _pillButton(
                    'Done',
                    btnBg,
                    fg,
                    () => Navigator.pop(context, _value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required bool looping,
    required String Function(int) label,
    required bool Function(int) isSelected,
    required ValueChanged<int> onChanged,
    required Color fg,
    required Color dim,
    double selectedSize = 44,
  }) {
    Widget item(int i) {
      final sel = isSelected(i);
      return Center(
        child: Text(
          label(i),
          style: TextStyle(
            fontSize: sel ? selectedSize : selectedSize * 0.75,
            color: sel ? fg : dim,
            fontWeight: sel ? FontWeight.w500 : FontWeight.w300,
          ),
        ),
      );
    }

    final children = List.generate(count, item);

    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _itemExtent,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 2.5,
      perspective: 0.002,
      overAndUnderCenterOpacity: 0.8,
      onSelectedItemChanged: (raw) => onChanged(((raw % count) + count) % count),
      childDelegate: looping
          ? ListWheelChildLoopingListDelegate(children: children)
          : ListWheelChildListDelegate(children: children),
    );
  }

  Widget _pillButton(String text, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Text(text, style: TextStyle(color: fg, fontSize: 17)),
          ),
        ),
      ),
    );
  }
}
