import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/core/theme/app_theme.dart';
import 'package:hulikamote_dashboard/features/blueprint/domain/tests_index.dart';
import 'package:hulikamote_dashboard/features/blueprint/presentation/widgets/tests_section.dart';

TestRef ref(String sentence, {String? outcome = 'passed'}) =>
    TestRef(file: 'hulikamote_backend/tests/engine/test_ledger.py', line: 10, name: 'test_${sentence.replaceAll(' ', '_')}', sentence: sentence, outcome: outcome);

TestsIndex index({int clips = 0}) => TestsIndex.fromJson({
      'generated': '2026-10-26 14:02',
      'real_footage': {'clips_in_registry': clips},
      'tests': [],
      'files': {},
    });

Future<void> pump(WidgetTester tester, AnchorTests? info, {TestsIndex? idx}) async {
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(body: SingleChildScrollView(child: TestsSection(info: info, index: idx ?? index()))),
  ));
}

void main() {
  testWidgets('lists the tests as sentences with their result, and how much of the code they run', (tester) async {
    await pump(
      tester,
      AnchorTests(
        tests: [ref('pedestrian lane flags car stopped past limit'), ref('pedestrian lane ignores short stop', outcome: 'failed')],
        total: 2,
        direct: 2,
        coveragePct: 92.4,
        exact: true,
      ),
    );

    expect(find.text("How it's tested"), findsOneWidget);
    expect(find.text('Pedestrian lane flags car stopped past limit'), findsOneWidget);
    expect(find.text('Pedestrian lane ignores short stop'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.textContaining('1 failing.'), findsOneWidget);
    expect(find.textContaining('2 tests, all written for this code.'), findsOneWidget);
    expect(find.text('92% of its lines run in tests'), findsOneWidget);
  });

  testWidgets('says plainly when no test runs the code', (tester) async {
    await pump(tester, const AnchorTests(tests: [], total: 0, direct: 0, coveragePct: 0, exact: true));

    expect(find.text('No test runs this code.'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
  });

  testWidgets('says when a function only runs inside other tests', (tester) async {
    await pump(tester, AnchorTests(tests: [ref('some other behaviour')], total: 40, direct: 0, coveragePct: 100, exact: true));

    expect(find.textContaining('none is written for it'), findsOneWidget);
    expect(find.text('and 39 more that run it indirectly'), findsOneWidget);
  });

  testWidgets('a settings-only violation says its rule is the shared class and how many tests name it', (tester) async {
    await pump(
      tester,
      AnchorTests(tests: [ref('pedestrian lane flags car')], total: 14, direct: 1, coveragePct: 100, exact: true, inheritedFrom: 'StoppedInZone'),
    );

    expect(find.textContaining('only holds settings; its rule is the shared StoppedInZone'), findsOneWidget);
    expect(find.textContaining('14 tests run that rule, 1 names this violation.'), findsOneWidget);
  });

  testWidgets('Flutter code is described by file, and is marked "not run" until the tests were run', (tester) async {
    await pump(tester, AnchorTests(tests: [ref('shows the title', outcome: null)], total: 1, direct: 0, coveragePct: null, exact: false));

    expect(find.textContaining('in test files that load this file'), findsOneWidget);
    expect(find.textContaining('Not run in this index.'), findsOneWidget);
    expect(find.textContaining('lines run in tests'), findsNothing); // no per-function numbers for Dart
  });

  testWidgets('a file the index does not know says how to rebuild it', (tester) async {
    await pump(tester, null);

    expect(find.textContaining('not in the tests index yet'), findsOneWidget);
  });

  testWidgets('a long list shows five and folds the rest behind "Show more"', (tester) async {
    final eight = [for (var i = 1; i <= 8; i++) ref('case number $i')];
    await pump(tester, AnchorTests(tests: eight, total: 8, direct: 8, coveragePct: 80, exact: true));

    expect(find.textContaining('Case number'), findsNWidgets(5));
    await tester.tap(find.text('Show 3 more'));
    await tester.pump();
    expect(find.textContaining('Case number'), findsNWidgets(8));
    expect(find.text('Show fewer'), findsOneWidget);
  });

  testWidgets('always reminds that passing tests are not accuracy on real footage', (tester) async {
    await pump(tester, AnchorTests(tests: [ref('x')], total: 1, direct: 1, coveragePct: 50, exact: true));
    expect(find.textContaining('not measured yet (no scored clips)'), findsOneWidget);

    await pump(tester, AnchorTests(tests: [ref('x')], total: 1, direct: 1, coveragePct: 50, exact: true), idx: index(clips: 6));
    expect(find.textContaining('6 scored clips'), findsOneWidget);
  });
}
