import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:repwise/main.dart';

void main() {
  testWidgets('Track weight button opens the Weight Tracker screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RepwiseApp());
    await tester.pumpAndSettle();

    // Workout tab is index 1 in the bottom NavigationBar.
    await tester.tap(find.text('Workout').last);
    await tester.pumpAndSettle();

    final trackWeightButton = find.byTooltip('Track weight');
    expect(trackWeightButton, findsOneWidget);

    await tester.tap(trackWeightButton);
    await tester.pumpAndSettle();

    expect(find.text('Weight Tracker'), findsOneWidget);
  });
}
