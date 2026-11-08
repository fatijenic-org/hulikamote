import 'dart:convert';
import 'dart:io';

import 'reference_models.dart';

/// A JSON object as `Map<String, dynamic>`, whatever type the map was built with (a literal `{}` is `Map<dynamic, dynamic>`).
Map<String, dynamic>? _map(Object? value) => value is Map ? value.cast<String, dynamic>() : null;

/// One test, as `tools/tests_index.py` recorded it.
class TestRef {
  const TestRef({required this.file, required this.line, required this.name, required this.sentence, required this.outcome});

  factory TestRef.fromJson(Map<String, dynamic> json) => TestRef(
        file: json['file'] as String,
        line: (json['line'] as num?)?.toInt() ?? 1,
        name: json['name'] as String? ?? '',
        sentence: json['sentence'] as String? ?? json['name'] as String? ?? '',
        outcome: json['outcome'] as String?,
      );

  /// Repository-relative path with forward slashes.
  final String file;
  final int line;
  final String name;

  /// The test name read as a sentence ("pedestrian lane ignores short stop").
  final String sentence;

  /// `passed`, `failed`, `skipped`, or null when the index was built without running these tests.
  final String? outcome;

  bool get passed => outcome == 'passed';
  bool get failed => outcome == 'failed';
}

/// What the Code Reference shows under the code of one [CodeAnchor].
class AnchorTests {
  const AnchorTests({
    required this.tests,
    required this.total,
    required this.direct,
    required this.coveragePct,
    required this.exact,
    this.mirrorTest,
    this.inheritedFrom,
  });

  /// The most relevant tests first (at most a handful; [total] is the real number).
  final List<TestRef> tests;
  final int total;

  /// The first [direct] tests were written for this code; the rest only run it through other code.
  final int direct;

  /// Share of this code's lines that run during the tests (Python only).
  final double? coveragePct;

  /// True when the numbers are for this one function (Python). False when they are for the whole file (Dart, or
  /// a name the index does not know).
  final bool exact;

  /// The test file that mirrors this source file, when there is one.
  final String? mirrorTest;

  /// A class that only holds settings has no code of its own: its tests are the ones of the shared class it is built
  /// on (for example `StoppedInZone`). Null for everything else.
  final String? inheritedFrom;

  bool get untested => total == 0;
  bool get anyFailing => tests.any((t) => t.failed);
  bool get hasResults => tests.any((t) => t.outcome != null);
}

/// The tests index: which tests protect which code. Built by `tools/tests_index.py` and read from
/// `docs/project_map/tests_index.json`, so it is only as fresh as its [generated] date.
class TestsIndex {
  TestsIndex._(this.generated, this.runs, this.clipsInRegistry, this._tests, this._files);

  factory TestsIndex.fromJson(Map<String, dynamic> json) => TestsIndex._(
        json['generated'] as String? ?? '',
        _map(json['runs']) ?? const {},
        (_map(json['real_footage'])?['clips_in_registry'] as num?)?.toInt() ?? 0,
        [for (final t in (json['tests'] as List? ?? const [])) TestRef.fromJson(_map(t)!)],
        _map(json['files']) ?? const {},
      );

  /// Reads the index from the repository at [root]. Null when it has not been built yet (or cannot be read).
  static TestsIndex? load(Directory root) {
    final sep = Platform.pathSeparator;
    final file = File('${root.path}${sep}docs${sep}project_map${sep}tests_index.json');
    if (!file.existsSync()) return null;
    try {
      return TestsIndex.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// When the index was built, e.g. `2026-10-26 14:02`.
  final String generated;

  /// Per test run (backend, training_lab, flutter): how many tests, passed, failed.
  final Map<String, dynamic> runs;

  /// How many clips with known answers the benchmark has. Zero means accuracy on real footage is not measured.
  final int clipsInRegistry;

  final List<TestRef> _tests;
  final Map<String, dynamic> _files;

  /// A Python anchor is `def name(` or `class Name`; anything else falls back to the whole file.
  static final RegExp _symbolName = RegExp(r'^(?:async\s+)?(?:def|class)\s+(\w+)');

  /// Null when the index does not know the file at all.
  AnchorTests? forAnchor(CodeAnchor anchor) {
    final file = _map(_files[anchor.file]);
    if (file == null) return null;

    final name = _symbolName.firstMatch(anchor.symbol.trimLeft())?.group(1);
    final symbols = _map(file['symbols']) ?? const {};
    final symbol = name == null ? null : _map(symbols[name]);
    final source = symbol ?? file;

    final ids = (source['tests'] as List? ?? const []).map((e) => (e as num).toInt());
    return AnchorTests(
      tests: [for (final i in ids) if (i >= 0 && i < _tests.length) _tests[i]],
      total: (source['tests_total'] as num?)?.toInt() ?? 0,
      direct: (source['tests_direct'] as num?)?.toInt() ?? 0,
      coveragePct: (source['coverage_pct'] as num?)?.toDouble(),
      exact: symbol != null,
      mirrorTest: file['mirror_test'] as String?,
      inheritedFrom: symbol?['inherited_from'] as String?,
    );
  }
}
