// Basic smoke test: app starts and shows the bottom tab bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ak47clk/main.dart';

void main() {
  testWidgets('App starts with the tab bar', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MyApp(prefs: prefs));
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
