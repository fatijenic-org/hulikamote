import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/violation_lab/data/violation_data.dart';
import 'package:hulikamote_dashboard/features/wiki/presentation/violation_lab/screens/violation_lab_screen.dart';

void main() {
  testWidgets('every violation lesson opens at all 5 steps without an error', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Collect every framework error. The lessons (copied from the standalone visualizer) put a few
    // list tiles inside colored boxes, which only triggers a debug hint about tap highlights: ignore that hint.
    final problems = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      // Skip two kinds of noise: the tap-highlight hint, and overflow warnings (the test font is much wider than the real one).
      if (text.contains('ink splashes may be invisible') || text.contains('overflowed by')) return;
      problems.add('${details.exception}'.split('\n').first);
    };

    String? firstProblem;
    try {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF3B82F6)),
        home: const Scaffold(body: ViolationLabScreen()),
      ));

      expect(violationsData.length, 13);
      const steps = ['1. Code & Math', '2. Naive Simulation', '3. Core Concept', '4. Real-World Setup', '5. Modern AI'];

      outer:
      for (final v in violationsData) {
        await tester.tap(find.widgetWithText(ListTile, v.title).first);
        await tester.pump(const Duration(milliseconds: 100));
        for (final step in steps) {
          await tester.ensureVisible(find.text(step));
          await tester.tap(find.text(step));
          await tester.pump(const Duration(milliseconds: 200));
          if (problems.isNotEmpty) {
            firstProblem = '${v.title} / $step: ${problems.first}';
            break outer;
          }
        }
      }
    } finally {
      FlutterError.onError = previous;
    }
    expect(firstProblem, isNull);
  });
}
