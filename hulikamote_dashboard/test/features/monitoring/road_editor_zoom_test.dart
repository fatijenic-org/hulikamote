import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/monitoring/domain/models/road_detect.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/road_zone_editor.dart';

/// The road editor is a scrolling page with the picture at the full width, and it zooms: the shapes scale with the picture.
const _size = Size(1280, 720);

// A shape near the middle of the picture, so it stays on screen while zooming about the centre.
const _shape = RoadArea(id: 'road-1', kind: 'road', polygon: [Offset(560, 300), Offset(720, 300), Offset(720, 420), Offset(560, 420)]);

late List<RoadArea> _areas;

Future<void> _pump(WidgetTester tester, {double width = 1100, double height = 760}) async {
  tester.view.physicalSize = const Size(1200, 900);                       // the default test window is only 800 wide
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _areas = [_shape];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: StatefulBuilder(
          builder: (context, setState) => RoadZoneEditor(
            frame: null,
            size: _size,
            areas: _areas,
            onChanged: (a) => setState(() => _areas = a),
            onReset: () {},
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

final _canvas = find.byKey(const ValueKey('road-canvas'));

/// Where a point of the picture is on the screen (the canvas rect already includes the zoom).
Offset _at(WidgetTester tester, Offset frame) {
  final box = tester.getRect(_canvas);
  return box.topLeft + frame * (box.width / _size.width);
}

String _level(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('road-zoom-level'))).data ?? '';

Future<void> _press(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('the picture takes the whole width and the page scrolls to the bottom of it', (tester) async {
    await _pump(tester, height: 400);                                       // far too short for the picture
    final before = tester.getRect(_canvas);
    expect(before.width, greaterThan(1000), reason: 'not squeezed into what is left over');
    expect(before.height, greaterThan(400), reason: 'taller than the room: the page scrolls');
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(_canvas).bottom, lessThanOrEqualTo(400 + 1), reason: 'scrolled down to the bottom of the picture');
  });

  testWidgets('+, - and the fit button zoom, and everything in the picture scales with it', (tester) async {
    await _pump(tester);
    expect(_level(tester), '100%');
    final width = tester.getRect(_canvas).width;
    await _press(tester, 'road-zoom-in');
    await _press(tester, 'road-zoom-in');
    expect(_level(tester), '196%');
    expect(tester.getRect(_canvas).width / width, closeTo(1.96, 0.001), reason: 'picture and shapes grow together');
    await _press(tester, 'road-zoom-out');
    expect(_level(tester), '140%');
    await _press(tester, 'road-zoom-fit');
    expect(_level(tester), '100%');
    expect(tester.getRect(_canvas).width, closeTo(width, 0.001));
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('road-zoom-out'))).onPressed, isNull, reason: 'cannot zoom out past the whole picture');
  });

  testWidgets('a point is dragged and a shape is selected at any zoom, in the picture\'s own pixels', (tester) async {
    await _pump(tester);
    await _press(tester, 'road-zoom-in');
    await _press(tester, 'road-zoom-in');
    await tester.tapAt(_at(tester, const Offset(640, 360)));                // inside the shape: select it
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('road-kind')), findsOneWidget);

    final k = tester.getRect(_canvas).width / _size.width;                  // screen pixels per picture pixel, zoom included
    await tester.dragFrom(_at(tester, const Offset(720, 300)), const Offset(-60, 40));
    await tester.pump(const Duration(milliseconds: 50));
    final moved = _areas.single.polygon[1];
    expect(moved.dx, closeTo(720 - 60 / k, 1.5));
    expect(moved.dy, closeTo(300 + 40 / k, 1.5));
    expect(_areas.single.polygon.length, 4);
  });

  testWidgets('zoomed in, dragging the empty picture moves the picture, not a shape', (tester) async {
    await _pump(tester);
    await _press(tester, 'road-zoom-in');
    await _press(tester, 'road-zoom-in');
    final before = tester.getRect(_canvas).topLeft;
    final drag = await tester.startGesture(_at(tester, const Offset(500, 330)), kind: PointerDeviceKind.mouse);   // empty picture, beside the shape and still on screen after zooming about the centre
    await drag.moveBy(const Offset(-80, -50));
    await drag.moveBy(const Offset(-10, -10));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 50));
    final after = tester.getRect(_canvas).topLeft;
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    expect(_areas.single.polygon, _shape.polygon, reason: 'no shape was touched');
  });

  testWidgets('Ctrl + wheel zooms about the cursor; a plain wheel does not zoom (it scrolls the page)', (tester) async {
    await _pump(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final over = _at(tester, const Offset(640, 360));
    await tester.sendEventToBinding(mouse.hover(over));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(_level(tester), '100%');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(_level(tester), isNot('100%'));
    expect(int.parse(_level(tester).replaceAll('%', '')), greaterThan(100));
  });
}
