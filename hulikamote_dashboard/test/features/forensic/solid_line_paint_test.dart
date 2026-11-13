import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:hulikamote_dashboard/features/forensic/data/object_previews.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/line_paint.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/solid_line_editor.dart';

import 'support/test_support.dart';

/// "Crossing a solid line", paint it: a saved line can be painted on the picture like road paint (style, width, wear, perspective, turn,
/// filmed look). The paint is a picture of the line: the rule judges the points. The pictures come from the backend.
const _rule = 'crossing_solid_line';

AnalysisDraft _draft() {
  final d = AnalysisDraft();
  d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
  d.toggle(_rule);
  d.zones(_rule).add(<String, dynamic>{'line': [[960.0, 900.0], [1000.0, 300.0]]});
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

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

Slider _slider(WidgetTester tester, String key) => tester.widget<Slider>(find.byKey(ValueKey(key)));

void main() {
  group('the look of the paint (pure)', () {
    test('defaults, limits and styles', () {
      expect(LinePaint.newLook(), {'style': 'solid_yellow', 'width': 1.0, 'wear': 0.2, 'taper': 0.6});
      expect(LinePaint.widthOf({'width': 99}), LinePaint.maxWidth);
      expect(LinePaint.widthOf({}), 1.0);
      expect(LinePaint.wearOf({'wear': -2}), 0.0);
      expect(LinePaint.taperOf({'taper': double.nan}), 0.6);
      expect(LinePaint.styleOf({'style': 'wavy'}), 'solid_yellow');
      expect(LinePaint.styleOf({'style': 'dashed_white'}), 'dashed_white');
      expect(LinePaint.styles.map((s) => s.$1), ['solid_yellow', 'solid_white', 'double_yellow', 'dashed_white']);
    });

    test('turning a line keeps its length and its middle, and a full turn back gives the line back', () {
      const line = [Offset(0.3, 0.8), Offset(0.5, 0.4), Offset(0.6, 0.3)];
      final turned = LinePaint.rotated(line, 10);
      expect(turned, isNot(line));
      double px(Offset a, Offset b) => Offset((a.dx - b.dx) * 1920, (a.dy - b.dy) * 1080).distance; // the turn keeps lengths in picture pixels
      double len(List<Offset> p) => px(p[0], p[1]) + px(p[1], p[2]);
      expect(len(turned), closeTo(len(line), 8));
      final back = LinePaint.rotated(LinePaint.rotated(line, 25), -25);
      for (var i = 0; i < line.length; i++) {
        expect((back[i] - line[i]).distance, lessThan(0.002));
      }
      expect(LinePaint.rotated(const [], 5), isEmpty);
      for (final p in LinePaint.rotated(const [Offset(0.01, 0.99), Offset(0.99, 0.01)], 80)) {
        expect(p.dx, inInclusiveRange(0.0, 1.0));
        expect(p.dy, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('in the editor', () {
    testWidgets('a line is not painted until it is switched on, and the paint controls appear with it', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      expect(d.zones(_rule).single.containsKey('look'), isFalse);
      expect(find.byKey(const ValueKey('solid-paint-look')), findsNothing);
      await _tapKey(tester, 'solid-paint-0');
      expect(d.zones(_rule).single['look'], LinePaint.newLook());
      expect(find.byKey(const ValueKey('solid-paint-look')), findsOneWidget);
      await _tapKey(tester, 'solid-paint-0');
      expect(d.zones(_rule).single.containsKey('look'), isFalse);
      expect(find.byKey(const ValueKey('solid-paint-look')), findsNothing);
    });

    testWidgets('style, width, wear and perspective are set on the selected line and reach the payload', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'solid-paint-0');
      await tester.ensureVisible(find.byKey(const ValueKey('solid-width')));
      await tester.tap(find.text('Double yellow'));
      await tester.pump();
      _slider(tester, 'solid-width').onChanged!(2.0);
      _slider(tester, 'solid-wear').onChanged!(0.7);
      _slider(tester, 'solid-taper').onChanged!(0.1);
      await tester.pump();
      final look = d.zones(_rule).single['look'] as Map;
      expect(look, {'style': 'double_yellow', 'width': 2.0, 'wear': 0.7, 'taper': 0.1});
      final sent = ((d.buildConfig()['per_violation_configs'] as Map)[_rule] as Map)['rois'] as List;
      expect((sent.single as Map)['look'], look);
      expect((sent.single as Map)['line'], [[960.0, 900.0], [1000.0, 300.0]]);
    });

    testWidgets('turning the line moves its points and keeps the paint settings', (tester) async {
      final d = _draft();
      await _pump(tester, d);
      await _tapKey(tester, 'solid-paint-0');
      final before = List.of(d.zones(_rule).single['line'] as List);
      await _tapKey(tester, 'solid-rotate-right');
      final after = d.zones(_rule).single['line'] as List;
      expect(after, isNot(before));
      expect(d.zones(_rule).single['look'], LinePaint.newLook());
      await _tapKey(tester, 'solid-rotate-left');
      final back = d.zones(_rule).single['line'] as List;
      for (var i = 0; i < 2; i++) {
        expect(((back[i][0] as num) - (before[i][0] as num)).abs(), lessThan(4));
        expect(((back[i][1] as num) - (before[i][1] as num)).abs(), lessThan(4));
      }
    });

    testWidgets('the realistic switch is saved for the analysis; a click on another line selects it; deleting keeps the selection right', (tester) async {
      final d = _draft();
      d.zones(_rule).add(<String, dynamic>{'line': [[300.0, 900.0], [400.0, 400.0]]});
      await _pump(tester, d);
      await _tapKey(tester, 'solid-paint-1');
      expect(find.text('PAINT OF LINE 2'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('solid-realistic')));
      await tester.tap(find.byKey(const ValueKey('solid-realistic')));
      await tester.pump();
      expect(d.config(_rule)['lines_realistic'], isFalse);
      await _tapKey(tester, 'solid-paint-0');
      expect(find.text('PAINT OF LINE 1'), findsOneWidget);
      await _tapKey(tester, 'solid-delete-0');
      expect(d.zones(_rule), hasLength(1));
      expect(find.byKey(const ValueKey('solid-paint-look')), findsNothing, reason: 'the selected line went with the delete');
    });
  });

  group('the paint pictures come from the backend', () {
    testWidgets('a painted line is asked for once and kept; a line with no look is never asked for', (tester) async {
      final asked = <Map<String, dynamic>>[];
      final api = ForensicApi(
        client: MockClient((req) async {
          if (req.url.path == '/api/forensic/overlay-line') {
            asked.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
            return http.Response.bytes(kTinyPng, 200, headers: {'x-offset-x': '900', 'x-offset-y': '280'});
          }
          return http.Response('{}', 404);
        }),
      );
      final previews = ObjectPreviews(api);
      const points = [
        [960.0, 900.0],
        [1000.0, 300.0],
      ];
      final look = LinePaint.newLook();
      expect(previews.peekLine(points, look, true), isNull);
      expect(previews.peekLine(points, look, true), isNull);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      expect(asked, hasLength(1));
      expect(asked.single['points'], [[960.0, 900.0], [1000.0, 300.0]]);
      expect(asked.single['realistic'], true);
      final got = previews.peekLine(points, look, true);
      expect(got, isNotNull);
      expect((got!.dx, got.dy), (900.0, 280.0));
      expect(previews.peekLine(points, {...look, 'style': 'dashed_white'}, true), isNull, reason: 'another look is another picture');
      previews.dispose();
    });
  });
}
