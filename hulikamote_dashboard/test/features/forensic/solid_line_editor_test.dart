import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/zone_geometry.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/solid_line_editor.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/test_support.dart';

/// "Crossing a solid line": nothing has to be drawn (the painted lines are found when the analysis starts), and a line that
/// is drawn can have any number of points, can be bent, and there can be several.
const _rule = 'crossing_solid_line';

AnalysisDraft _draft() {
  final d = AnalysisDraft();
  d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
  d.toggle(_rule);
  return d;
}

Future<void> _pump(WidgetTester tester, AnalysisDraft d, {ForensicApi? api}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: d,
          builder: (_, _) => SolidLineEditor(draft: d, violationKey: _rule, frame: MemoryImage(kTinyPng), api: api),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Rect _canvas(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('solid-canvas')));

/// A spot on the picture, as a share of its width and height.
Offset _at(WidgetTester tester, double fx, double fy) {
  final r = _canvas(tester);
  return Offset(r.left + fx * r.width, r.top + fy * r.height);
}

Future<void> _click(WidgetTester tester, double fx, double fy) async {
  await tester.tapAt(_at(tester, fx, fy));
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('solid-save')));
  await tester.pump();
}

List<dynamic> _lines(AnalysisDraft d) => d.zones(_rule);

/// Drags with a mouse (a small slop, like the real app on a desktop).
Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await g.moveTo(Offset.lerp(from, to, 0.5)!);
  await g.moveTo(to);
  await g.up();
  await tester.pump();
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data ?? '';

void main() {
  group('nothing to draw', () {
    testWidgets('with no line drawn the rule is ready and says the lines are found by themselves', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      expect(d.zonesReady(_rule), isTrue);
      expect(d.canStart, isTrue);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('solid-auto'))).value, isTrue);
      expect(_text(tester, 'solid-empty'), contains('the painted solid lines are found in the video'));
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('solid-save'))).onPressed, isNull);
    });

    testWidgets('turning the search off with no line drawn blocks starting, and says why', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await tester.tap(find.byKey(const ValueKey('solid-auto')));
      await tester.pump();
      expect(d.config(_rule)['auto_lines'], isFalse);
      expect(d.zonesReady(_rule), isFalse);
      expect(_text(tester, 'solid-empty'), contains('automatic search is off'));
      await tester.tap(find.byKey(const ValueKey('solid-auto')));
      await tester.pump();
      expect(d.zonesReady(_rule), isTrue);
    });
  });

  group('drawing a line', () {
    testWidgets('two points are the least, three or more follow a curve, and no road section is stored', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _click(tester, 0.2, 0.8);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('solid-save'))).onPressed, isNull, reason: 'one point is no line');
      await _click(tester, 0.4, 0.6);
      await _click(tester, 0.8, 0.5);
      expect(_text(tester, 'solid-count'), startsWith('3 points'));
      await _save(tester);

      expect(_lines(d), hasLength(1));
      final zone = _lines(d).single as Map;
      expect(zone.containsKey('polygon'), isFalse, reason: 'the road section is not needed');
      final line = zone['line'] as List;
      expect(line, hasLength(3));
      expect(line[0][0], closeTo(0.2 * 1920, 8));
      expect(line[0][1], closeTo(0.8 * 1080, 8));
      expect(line[2][0], closeTo(0.8 * 1920, 8));
      expect(_text(tester, 'solid-count'), startsWith('Click along the solid line'));       // ready for the next one
      expect(find.text('Line 1  ·  3 points'), findsOneWidget);

      final sent = d.buildConfig()['per_violation_configs'] as Map;
      expect(((sent[_rule] as Map)['rois'] as List).single['line'], hasLength(3));
    });

    testWidgets('several lines can be saved, each on its own, and one can be deleted', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      for (final y in [0.3, 0.7]) {
        await _click(tester, 0.2, y);
        await _click(tester, 0.8, y);
        await _save(tester);
      }
      expect(_lines(d), hasLength(2));
      expect(find.byKey(const ValueKey('solid-saved-1')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('solid-delete-0'))); // the side panel scrolls on its own
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('solid-delete-0')));
      await tester.pump();
      expect(_lines(d), hasLength(1));
      expect(((_lines(d).single as Map)['line'] as List)[0][1], closeTo(0.7 * 1080, 8), reason: 'the first line went, the second stayed');
    });

    testWidgets('undo and clear work on the line being drawn', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _click(tester, 0.2, 0.3);
      await _click(tester, 0.5, 0.3);
      await tester.tap(find.byKey(const ValueKey('solid-undo')));
      await tester.pump();
      expect(_text(tester, 'solid-count'), startsWith('1 point, at least 2'));
      await tester.tap(find.byKey(const ValueKey('solid-clear')));
      await tester.pump();
      expect(_text(tester, 'solid-count'), startsWith('Click along the solid line'));
    });

    testWidgets('an unsaved line is not part of the analysis', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _click(tester, 0.2, 0.3);
      await _click(tester, 0.5, 0.3);
      expect(_lines(d), isEmpty);
    });
  });

  group('bending a saved line', () {
    Future<AnalysisDraft> withLine(WidgetTester tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _click(tester, 0.2, 0.5);
      await _click(tester, 0.8, 0.5);
      await _save(tester);
      return d;
    }

    testWidgets('dragging a point moves it', (tester) async {
      final d = await withLine(tester);
      await _drag(tester, _at(tester, 0.8, 0.5), _at(tester, 0.8, 0.2));
      final line = (_lines(d).single as Map)['line'] as List;
      expect(line, hasLength(2));
      expect(line[1][1], closeTo(0.2 * 1080, 8));
      expect(line[0][1], closeTo(0.5 * 1080, 8), reason: 'the other point stayed');
    });

    testWidgets('dragging the middle of the line adds a point there: that is how it bends', (tester) async {
      final d = await withLine(tester);
      await _drag(tester, _at(tester, 0.5, 0.5), _at(tester, 0.5, 0.25));
      final line = (_lines(d).single as Map)['line'] as List;
      expect(line, hasLength(3));
      expect(line[1][0], closeTo(0.5 * 1920, 8));
      expect(line[1][1], closeTo(0.25 * 1080, 8));
      expect(find.text('Line 1  ·  3 points'), findsOneWidget);
    });

    testWidgets('a right-click removes a point, but never below two', (tester) async {
      final d = await withLine(tester);
      await _drag(tester, _at(tester, 0.5, 0.5), _at(tester, 0.5, 0.25)); // now 3 points
      await tester.tapAt(_at(tester, 0.5, 0.25), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(((_lines(d).single as Map)['line'] as List), hasLength(2));
      await tester.tapAt(_at(tester, 0.8, 0.5), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(((_lines(d).single as Map)['line'] as List), hasLength(2));
      expect(_text(tester, 'solid-notice'), contains('at least 2 points'));
    });

    testWidgets('a point of the line being drawn can be dragged too', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _click(tester, 0.2, 0.5);
      await _click(tester, 0.8, 0.5);
      await _drag(tester, _at(tester, 0.8, 0.5), _at(tester, 0.8, 0.8));
      await _save(tester);
      expect((((_lines(d).single as Map)['line'] as List)[1] as List)[1], closeTo(0.8 * 1080, 8));
    });
  });

  group('showing what the automatic search finds', () {
    testWidgets('the lines it finds are added as ordinary lines to check and fix by hand', (tester) async {
      final d = _draft();
      final api = ForensicApi(
        baseUrl: 'http://test',
        client: MockClient((req) async {
          expect(req.url.path, '/api/forensic/road-markings');
          return http.Response(
            jsonEncode({
              'zones': {
                _rule: [
                  {
                    'polygon': [[0, 0], [10, 0], [10, 10]],
                    'ui_vector': [[960.0, 150.0], [480.0, 1050.0]],
                  },
                ],
              },
              'message': null,
            }),
            200,
          );
        }),
      );
      await _pump(tester, d, api: api);
      await tester.tap(find.byKey(const ValueKey('solid-find')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_lines(d), hasLength(1));
      final zone = _lines(d).single as Map;
      expect(zone['line'], [[960.0, 150.0], [480.0, 1050.0]]);
      expect(zone.containsKey('polygon'), isFalse);
      expect(_text(tester, 'solid-notice'), contains('Added 1 line'));
    });

    testWidgets('when it finds nothing it says why and adds nothing', (tester) async {
      final d = _draft();
      final api = ForensicApi(
        baseUrl: 'http://test',
        client: MockClient((req) async => http.Response(jsonEncode({'zones': <String, dynamic>{}, 'message': 'Not enough traffic movement.'}), 200)),
      );
      await _pump(tester, d, api: api);
      await tester.tap(find.byKey(const ValueKey('solid-find')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_lines(d), isEmpty);
      expect(_text(tester, 'solid-notice'), 'Not enough traffic movement.');
    });
  });

  group('ZoneGeometry.nearSegment', () {
    const canvas = Size(1000, 500);

    test('finds the piece of a bent line under the pointer and the spot on it', () {
      const line = [Offset(0.1, 0.5), Offset(0.5, 0.5), Offset(0.5, 0.1)];
      final onFirst = ZoneGeometry.nearSegment(line, const Offset(300, 255), canvas)!;
      expect(onFirst.segment, 0);
      expect(onFirst.point.dx, closeTo(0.3, 1e-9));
      expect(onFirst.point.dy, closeTo(0.5, 1e-9));
      final onSecond = ZoneGeometry.nearSegment(line, const Offset(505, 120), canvas)!;
      expect(onSecond.segment, 1);
      expect(onSecond.point.dx, closeTo(0.5, 1e-9));
    });

    test('nothing when the pointer is farther than the radius, or the line has fewer than two points', () {
      const line = [Offset(0.1, 0.5), Offset(0.5, 0.5)];
      expect(ZoneGeometry.nearSegment(line, const Offset(300, 300), canvas), isNull);
      expect(ZoneGeometry.nearSegment(const [Offset(0.1, 0.5)], const Offset(100, 250), canvas), isNull);
      expect(ZoneGeometry.nearSegment(const [], const Offset(100, 250), canvas), isNull);
    });
  });
}
