import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/blueprint/domain/reference_models.dart';
import 'package:hulikamote_dashboard/features/blueprint/domain/tests_index.dart';

const _ledger = 'hulikamote_backend/engine/ledger.py';

Map<String, dynamic> sampleIndex() => {
      'generated': '2026-10-26 14:02',
      'runs': {
        'backend': {'tests': 3, 'passed': 2, 'failed': 1}
      },
      'real_footage': {'clips_in_registry': 0},
      'tests': [
        {'file': 'hulikamote_backend/tests/engine/test_ledger.py', 'line': 49, 'name': 'test_pedestrian_lane_flags_car', 'sentence': 'pedestrian lane flags car', 'outcome': 'passed'},
        {'file': 'hulikamote_backend/tests/engine/test_ledger.py', 'line': 55, 'name': 'test_pedestrian_lane_ignores_short_stop', 'sentence': 'pedestrian lane ignores short stop', 'outcome': 'failed'},
        {'file': 'hulikamote_dashboard/test/x_test.dart', 'line': 7, 'name': 'shows the title', 'sentence': 'shows the title', 'outcome': null},
      ],
      'files': {
        _ledger: {
          'lang': 'python',
          'coverage_pct': 71.4,
          'mirror_test': 'hulikamote_backend/tests/engine/test_ledger.py',
          'tests_total': 3,
          'tests': [0, 1],
          'symbols': {
            'evaluate_pedestrian_lane': {'qualname': 'ActiveLedgerManager.evaluate_pedestrian_lane', 'line': 506, 'coverage_pct': 92.0, 'tests_total': 2, 'tests_direct': 1, 'tests': [0, 1]},
            'ActiveLedgerManager': {'qualname': 'ActiveLedgerManager', 'line': 156, 'coverage_pct': 60.0, 'tests_total': 2, 'tests_direct': 2, 'tests': [0, 1]},
            'PedestrianLane': {'qualname': 'PedestrianLane', 'kind': 'class', 'line': 9, 'coverage_pct': 100.0, 'tests_total': 2, 'tests_direct': 1, 'tests': [0, 1], 'inherited_from': 'StoppedInZone'},
            'never_run': {'qualname': 'never_run', 'line': 900, 'coverage_pct': 0.0, 'tests_total': 0, 'tests_direct': 0, 'tests': []},
          },
        },
        'hulikamote_dashboard/lib/x.dart': {'lang': 'dart', 'coverage_pct': null, 'mirror_test': null, 'tests_total': 1, 'tests': [2], 'symbols': {}},
      },
    };

void main() {
  final index = TestsIndex.fromJson(sampleIndex());

  test('finds the tests of one Python function from its anchor', () {
    final found = index.forAnchor(const CodeAnchor(_ledger, 'def evaluate_pedestrian_lane('))!;

    expect(found.exact, isTrue);
    expect(found.total, 2);
    expect(found.direct, 1); // the first of the listed tests was written for it
    expect(found.coveragePct, 92.0);
    expect(found.tests.map((t) => t.name), ['test_pedestrian_lane_flags_car', 'test_pedestrian_lane_ignores_short_stop']);
    expect(found.tests.first.passed, isTrue);
    expect(found.tests.last.failed, isTrue);
    expect(found.anyFailing, isTrue);
    expect(found.mirrorTest, 'hulikamote_backend/tests/engine/test_ledger.py');
  });

  test('a class anchor works the same way', () {
    final found = index.forAnchor(const CodeAnchor(_ledger, 'class ActiveLedgerManager'))!;

    expect(found.exact, isTrue);
    expect(found.direct, 2);
  });

  test('a settings-only class takes the tests of the shared class it is built on, and says where they come from', () {
    final found = index.forAnchor(const CodeAnchor(_ledger, 'class PedestrianLane'))!;

    expect(found.inheritedFrom, 'StoppedInZone');
    expect(found.total, 2);
    expect(found.direct, 1);
    expect(index.forAnchor(const CodeAnchor(_ledger, 'class ActiveLedgerManager'))!.inheritedFrom, isNull);
  });

  test('a function that no test runs says so', () {
    final found = index.forAnchor(const CodeAnchor(_ledger, 'def never_run('))!;

    expect(found.untested, isTrue);
    expect(found.tests, isEmpty);
    expect(found.coveragePct, 0.0);
  });

  test('a name the index does not know falls back to the whole file', () {
    final found = index.forAnchor(const CodeAnchor(_ledger, 'SOME_CONSTANT = '))!;

    expect(found.exact, isFalse);
    expect(found.total, 3);
    expect(found.coveragePct, 71.4);
  });

  test('Dart code is described by file: no per-function numbers, and no result until the tests have been run', () {
    final found = index.forAnchor(const CodeAnchor('hulikamote_dashboard/lib/x.dart', 'Widget build('))!;

    expect(found.exact, isFalse);
    expect(found.coveragePct, isNull);
    expect(found.total, 1);
    expect(found.hasResults, isFalse);
  });

  test('a file the index has never seen gives null, so the screen can say it is missing', () {
    expect(index.forAnchor(const CodeAnchor('hulikamote_backend/engine/new_file.py', 'def f(')), isNull);
  });

  test('keeps the date, the run summaries and how many real-footage clips are scored', () {
    expect(index.generated, '2026-10-26 14:02');
    expect(index.runs['backend']['failed'], 1);
    expect(index.clipsInRegistry, 0);
  });

  test('load reads docs/project_map/tests_index.json, and is null when it is missing or broken', () {
    final root = Directory.systemTemp.createTempSync('tests_index_test');
    addTearDown(() => root.deleteSync(recursive: true));
    expect(TestsIndex.load(root), isNull); // nothing built yet

    final dir = Directory('${root.path}${Platform.pathSeparator}docs${Platform.pathSeparator}project_map')..createSync(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}tests_index.json');

    file.writeAsStringSync('not json');
    expect(TestsIndex.load(root), isNull);

    file.writeAsStringSync(jsonEncode(sampleIndex()));
    expect(TestsIndex.load(root)!.generated, '2026-10-26 14:02');
  });
}
