import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/monitoring/domain/models/detection.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/flow_controls.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/video_feed_widget.dart';

const _arrows = [FlowArrow(100, 100, 160, 100), FlowArrow(100, 200, 160, 200)];

Widget _painted(FlowInfo? flow, {bool showFlow = true}) => MaterialApp(
  home: SizedBox(
    width: 640,
    height: 360,
    child: CustomPaint(painter: BoundingBoxPainter(const [], streamWidth: 640, streamHeight: 360, flow: flow, showFlow: showFlow), size: Size.infinite),
  ),
);

final _ours = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BoundingBoxPainter);

void main() {
  test('a frame carries the learned flow, and a frame without one carries none', () {
    final frame = VideoFrame.fromJson({
      'type': 'frame',
      'mock': false,
      'detections': [],
      'timestamp': 't',
      'flow': {
        'learning': true,
        'counterflow': true,
        'reversed': true,
        'cells': 12,
        'arrows': [
          {'x1': 100.5, 'y1': 100, 'x2': 160, 'y2': 100},
        ],
      },
    });
    expect(frame.flow!.learning && frame.flow!.counterflow && frame.flow!.reversed, isTrue);
    expect(frame.flow!.cells, 12);
    expect(frame.flow!.arrows.single.x1, 100.5);
    expect(VideoFrame.fromJson({'type': 'frame', 'mock': false, 'detections': [], 'timestamp': 't'}).flow, isNull);
  });

  group('the arrows on the live picture', () {
    testWidgets('are drawn when the switch is on and hidden when it is off', (tester) async {
      await tester.pumpWidget(_painted(const FlowInfo(learning: true, cells: 12, arrows: _arrows)));
      expect(_ours, paints..path());
      await tester.pumpWidget(_painted(const FlowInfo(learning: true, cells: 12, arrows: _arrows), showFlow: false));
      expect(_ours, isNot(paints..path()));
    });

    testWidgets('nothing is drawn for a flow that is not learned yet', (tester) async {
      await tester.pumpWidget(_painted(const FlowInfo(learning: true)));
      expect(_ours, isNot(paints..path()));
      expect(_ours, isNot(paints..rrect()));
    });

    testWidgets('the TEST label is drawn while the flow is reversed, even with the arrows hidden', (tester) async {
      await tester.pumpWidget(_painted(const FlowInfo(learning: true, counterflow: true, reversed: true, arrows: _arrows), showFlow: false));
      expect(_ours, paints..rrect());
      await tester.pumpWidget(_painted(const FlowInfo(learning: true, counterflow: true, arrows: _arrows)));
      expect(_ours, isNot(paints..rrect()));                                   // normal flow: no label
    });
  });

  group('the flow controls', () {
    Future<List<Object>> pump(WidgetTester tester, Map flow, {bool showArrows = true, bool busy = false}) async {
      final calls = <Object>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: FlowControls(
              flow: flow,
              showArrows: showArrows,
              busy: busy,
              onShowArrows: (v) => calls.add('arrows:$v'),
              onReverse: (v) => calls.add('reverse:$v'),
              onRelearn: () => calls.add('relearn'),
            ),
          ),
        ),
      ));
      return calls;
    }

    testWidgets('switch the arrows, reverse the flow, learn it again', (tester) async {
      final calls = await pump(tester, {'learning': true, 'counterflow': true, 'reversed': false, 'cells': 20});
      expect(find.text('Flow learned'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('flow-arrows-toggle')));
      await tester.tap(find.byKey(const ValueKey('flow-reverse-toggle')));
      await tester.tap(find.byKey(const ValueKey('flow-relearn')));
      expect(calls, ['arrows:false', 'reverse:true', 'relearn']);               // the arrows were on, the flow was normal
    });

    testWidgets('say when the flow is not learned yet, and warn while the test is on', (tester) async {
      await pump(tester, {'learning': true, 'counterflow': true, 'reversed': true, 'cells': 0});
      expect(find.text('Learning the flow…'), findsOneWidget);
      expect(find.text('Test on: tickets made now are tests'), findsOneWidget);
    });

    testWidgets('while an action is on its way the reverse switch and the relearn button wait', (tester) async {
      final calls = await pump(tester, {'learning': true, 'counterflow': true, 'cells': 5}, busy: true);
      await tester.tap(find.byKey(const ValueKey('flow-reverse-toggle')));
      await tester.tap(find.byKey(const ValueKey('flow-relearn')));
      expect(calls, isEmpty);
    });

    testWidgets('Counterflow with drawn zones has the reverse switch but no arrows to hide', (tester) async {
      await pump(tester, {'learning': false, 'counterflow': true, 'reversed': false, 'cells': 0});
      expect(find.byKey(const ValueKey('flow-reverse-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('flow-arrows-toggle')), findsNothing);
      expect(find.byKey(const ValueKey('flow-relearn')), findsNothing);
    });

    testWidgets('show nothing when no rule uses the flow', (tester) async {
      await pump(tester, {'learning': false, 'counterflow': false});
      expect(find.byType(FilterChip), findsNothing);
    });
  });
}
