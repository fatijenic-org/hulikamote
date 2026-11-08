import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/blueprint/data/reference_data.dart';
import 'package:hulikamote_dashboard/features/blueprint/domain/code_reader.dart';
import 'package:hulikamote_dashboard/features/blueprint/domain/reference_models.dart';

/// The repository root: the tests run from hulikamote_dashboard/.
Directory get repoRoot => Directory.current.parent;

void main() {
  group('CodeReader', () {
    const python = '''
import math

@router.get("/x")
async def outer(a, b):
    """Doc."""
    total = a + b

    if total:
        return total
    return 0


def next_one():
    pass

class Box:
    def long_signature(
        self,
        value: int,
    ) -> int:
        return value
''';

    test('a Python function runs to where the indentation falls back, with its decorator', () {
      final s = CodeReader.extract(python, 'async def outer(', dart: false)!;
      expect(s.startLine, 3);                                   // the decorator line is included
      expect(s.lines.first, '@router.get("/x")');
      expect(s.lines.last, '    return 0');
      expect(s.lines.any((l) => l.contains('next_one')), isFalse);
    });

    test('a signature over several lines still finds its body', () {
      final s = CodeReader.extract(python, 'def long_signature(', dart: false)!;
      expect(s.lines.last.trim(), 'return value');
      expect(s.lines.first, 'def long_signature(');             // flush left after the shared indent is removed
    });

    test('a Dart method ends where its braces balance', () {
      const dart = '''
class A {
  void one() {
    if (x) {
      y();
    }
  }

  Future<void> two() => _run(() async {
        await z();
      });

  int three() => 3;
}
''';
      expect(CodeReader.extract(dart, 'void one(', dart: true)!.lines.length, 5);
      expect(CodeReader.extract(dart, 'Future<void> two(', dart: true)!.lines.length, 3);
      expect(CodeReader.extract(dart, 'int three(', dart: true)!.lines, ['int three() => 3;']);
    });

    test('an unknown symbol is reported as missing', () {
      expect(CodeReader.extract(python, 'def nothing(', dart: false), isNull);
    });

    test('very long blocks are cut and say so', () {
      final long = 'def big():\n${List.generate(300, (i) => '    x$i = $i').join('\n')}\n';
      final s = CodeReader.extract(long, 'def big(', dart: false)!;
      expect(s.lines.length, CodeReader.maxLines);
      expect(s.truncated, isTrue);
    });
  });

  group('the content', () {
    final all = ReferenceData.all;

    test('every slice has a unique id, and every recipe ingredient exists', () {
      final ids = all.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final s in all) {
        for (final ingredient in s.recipe) {
          expect(ReferenceData.byId(ingredient), isNotNull, reason: '${s.id} lists the unknown "$ingredient"');
        }
        expect(s.recipe.contains(s.id), isFalse, reason: '${s.id} lists itself');
      }
    });

    test('every category has a ladder, and a slice stays small enough to read at a glance', () {
      for (final c in ReferenceCategory.values) {
        expect(ReferenceData.inCategory(c), isNotEmpty, reason: c.title);
      }
      for (final s in all) {
        expect(s.title.length, lessThanOrEqualTo(42), reason: '${s.id} title');
        expect(s.short.length, lessThanOrEqualTo(24), reason: '${s.id} short');
        expect(s.says.length, lessThanOrEqualTo(260), reason: '${s.id} says too much');
        expect(s.recipe.length, lessThanOrEqualTo(4), reason: '${s.id} recipe');
        expect(s.code, isNotEmpty, reason: '${s.id} shows no code');
        expect(s.code.length, lessThanOrEqualTo(2), reason: '${s.id} code tabs');
      }
    });

    test('all twenty-five violations have their slice', () {
      final violationSlices = all.where((s) =>
          s.category == ReferenceCategory.violations &&
          (s.group == 'Put two together' || s.group == 'People and models') &&
          s.id != 'r_autoflow'); // the same violation as r_counterflow, without a drawn zone
      expect(violationSlices.length, 25);
    });

    test('every pointer into the code resolves in the real files (so the reference cannot drift)', () {
      for (final s in all) {
        for (final anchor in s.code) {
          final snippet = CodeReader.read(repoRoot, anchor);
          expect(snippet, isNotNull, reason: '${s.id}: "${anchor.symbol}" not found in ${anchor.file}');
          expect(snippet!.lines.length, greaterThanOrEqualTo(2), reason: '${s.id}: "${anchor.symbol}" is empty');
        }
      }
    });
  });
}
