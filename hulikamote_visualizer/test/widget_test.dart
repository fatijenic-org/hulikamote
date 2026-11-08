// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hulikamote_visualizer/main.dart';

void main() {
  testWidgets('Visualizer app loads smoke test', (WidgetTester tester) async {
    // Set a desktop resolution typical for the visualizer
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Build our app and trigger a frame.
    await tester.pumpWidget(HuliKamoteVisualizerApp());
    await tester.pumpAndSettle();

    // Verify that title and core tabs render
    expect(find.text('Traffic Violation Logic & Physics'), findsOneWidget);
    expect(find.text('💻 1. Raw Code & Math'), findsOneWidget);
    expect(find.text('🟢 5. Modern AI'), findsOneWidget);
  });
}
