import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/core/widgets/code_inspector_tooltip.dart';

void main() {
  const sampleStages = [
    CodeTraceStage(
      stageTitle: '1. UI Display',
      stageRole: 'Presentation Layer',
      filePath: 'lib/features/forensic/presentation/widgets/decision_panel.dart',
      startLine: 104,
      endLine: 131,
      language: 'dart',
      description: 'Displays the button on screen',
      codeSnippet: 'final rejected = status == ReviewStatus.rejected;\n'
          'FilledButton.icon(\n'
          '    onPressed: busy ? null : () => onDecide(ReviewStatus.pending),\n'
          '    label: const Text("False alarm"),\n'
          ')',
    ),
    CodeTraceStage(
      stageTitle: '2. Controller State',
      stageRole: 'Domain Controller',
      filePath: 'lib/features/forensic/domain/review_controller.dart',
      startLine: 270,
      endLine: 318,
      language: 'dart',
      description: 'Updates state optimistically',
      codeSnippet: 'Future<bool> decide(String uid, ReviewStatus status) async {\n'
          '    _status[uid] = status;\n'
          '    notifyListeners();\n'
          '    return true;\n'
          '}',
    ),
  ];

  Widget buildTestSubject({bool showBadge = false}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: CodeInspectorTooltip(
            title: 'Test Action',
            stages: sampleStages,
            showBadge: showBadge,
            child: const ElevatedButton(
              onPressed: null,
              child: Text('Click me'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders child widget and shows tooltip on hover', (tester) async {
    await tester.pumpWidget(buildTestSubject());
    expect(find.text('Click me'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.text('Click me')));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.byType(Tooltip), findsOneWidget);
  });

  testWidgets('secondary click opens the FullCodeTraceDialog with stages', (tester) async {
    await tester.pumpWidget(buildTestSubject(showBadge: true));

    // Secondary click (right click)
    await tester.tap(find.text('Click me'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('COMPLETE CODE TRACKING: TEST ACTION'), findsOneWidget);
    expect(find.text('1. UI Display'), findsOneWidget);
    expect(find.text('2. Controller State'), findsOneWidget);
    expect(find.text('Open in VS Code'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Next Stage'), findsOneWidget);

    // Navigate to next stage
    await tester.tap(find.text('Next Stage'));
    await tester.pumpAndSettle();

    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('Stage 2 of 2'), findsOneWidget);
  });
}
