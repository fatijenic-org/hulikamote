import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/harvest_labeling.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/screens/forensic_analyzer_screen.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/harvest_categories_view.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/harvest_labeler.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart' show RunSummary;
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';

import 'support/test_support.dart';

/// Opens the labeler as the app does (a full-screen route over everything) from a plain button.
Future<void> _openLabeler(WidgetTester tester, FakeLabeling labeling, String model, {String? taskId}) async {
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('open'),
            onPressed: () => openHarvestLabeler(context, labeling: labeling, model: labeling.info(model), taskId: taskId),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('open')));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1)); // let the page slide-in finish, or positions move under the pointer
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Rect _canvas(WidgetTester tester) => tester.getRect(find.byKey(const Key('labeler-canvas')));

/// Where the picture really is on screen, zoom included (getRect keeps the unzoomed size).
Rect _shown(WidgetTester tester) {
  final f = find.byKey(const Key('labeler-canvas'));
  return Rect.fromPoints(tester.getTopLeft(f), tester.getBottomRight(f));
}

bool _enabled(WidgetTester tester, String key) => tester.widget<FilledButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  setUpAll(loadRoboto);

  group('the labeler: one picture at a time', () {
    testWidgets('shows the first picture; "Looks right" keeps the guessed boxes and moves on', (tester) async {
      final l = FakeLabeling();
      await _openLabeler(tester, l, 'plate_specialist', taskId: 't1');
      expect(find.byKey(const Key('labeler-progress')), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('Plates'), findsOneWidget);
      expect(l.asked, contains('t1')); // only the pictures of that analysis were asked for
      expect(_enabled(tester, 'looks-right'), isTrue);

      await _tap(tester, find.byKey(const Key('looks-right')));
      expect(l.saved['a1'], [
        [0, .5, .5, .4, .3],
      ]);
      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('a picture with no guess cannot be accepted until a box is drawn; Nothing here and Not sure are answers too', (tester) async {
      final l = FakeLabeling();
      await _openLabeler(tester, l, 'plate_specialist');
      await _tap(tester, find.byKey(const Key('looks-right')));
      expect(find.text('2 of 3'), findsOneWidget);
      expect(_enabled(tester, 'looks-right'), isFalse); // nothing to confirm on a bare picture

      await _tap(tester, find.byKey(const Key('nothing-here')));
      expect(l.saved['a2'], isEmpty); // "nothing here" is saved as an empty answer
      expect(find.text('3 of 3'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('not-sure')));
      expect(l.skipped, ['a3']);
      expect(find.byKey(const Key('labeler-done')), findsOneWidget);
      expect(find.text('All done'), findsOneWidget);
    });

    testWidgets('dragging draws a box where the finger went down; a tiny drag draws nothing', (tester) async {
      final l = FakeLabeling();
      await _openLabeler(tester, l, 'plate_specialist');
      await _tap(tester, find.byKey(const Key('nothing-here'))); // a1 answered, now a2 (no guess)
      expect(find.text('2 of 3'), findsOneWidget);

      final r = _canvas(tester);
      await tester.dragFrom(r.topLeft + Offset(r.width * .2, r.height * .2), Offset(r.width * .4, r.height * .3));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_enabled(tester, 'looks-right'), isTrue);
      await _tap(tester, find.byKey(const Key('looks-right')));
      final box = l.saved['a2']!.single;
      expect(box[0], 0);
      expect(box[1], closeTo(.4, .02));
      expect(box[2], closeTo(.35, .02));
      expect(box[3], closeTo(.4, .02));
      expect(box[4], closeTo(.3, .02));
    });

    testWidgets('pulling a corner fixes a box, dragging inside moves it, and Delete removes it', (tester) async {
      final l = FakeLabeling();
      await _openLabeler(tester, l, 'plate_specialist');
      final r = _canvas(tester);
      // pick the guessed box (centre .5 .5, size .4 x .3), then pull its bottom-right corner out to (.8, .8)
      await tester.tapAt(r.center);
      await tester.pump(const Duration(milliseconds: 100));
      final corner = r.topLeft + Offset(r.width * .7, r.height * .65);
      await tester.dragFrom(corner, Offset(r.width * .1, r.height * .15));
      await tester.pump(const Duration(milliseconds: 100));
      await _tap(tester, find.byKey(const Key('looks-right')));
      final fixed = l.saved['a1']!.single;
      expect(fixed[1], closeTo(.55, .02)); // from x .3..(.8)
      expect(fixed[3], closeTo(.5, .02));
      expect(fixed[4], closeTo(.45, .02));

      // the third picture has two guessed boxes: pick one and remove it with Delete (the second has none: skip past it)
      await _tap(tester, find.byKey(const Key('nothing-here')));
      await tester.tapAt(r.topLeft + Offset(r.width * .3, r.height * .3));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 150));
      expect(l.saved['a3'], hasLength(1)); // only the other box is left
      expect(l.saved['a3']!.single[1], closeTo(.7, .01));
    });

    testWidgets('the keyboard does it all: Enter, N, S, arrows, Esc', (tester) async {
      final l = FakeLabeling();
      await _openLabeler(tester, l, 'plate_specialist');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 150));
      expect(l.saved.keys, ['a1']);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump(const Duration(milliseconds: 150));
      expect(l.saved['a2'], isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // back to the picture before
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('2 of 3'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump(const Duration(milliseconds: 150));
      expect(l.skipped, ['a2']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byKey(const Key('labeler-progress')), findsNothing);
      expect(find.byKey(const Key('open')), findsOneWidget);
    });

    testWidgets('a model with several kinds of box shows them as colours to pick; the picked one is what gets drawn', (tester) async {
      final l = FakeLabeling()..pictures['helmet_specialist'] = [FakeLabeling.item('h1')];
      await _openLabeler(tester, l, 'helmet_specialist');
      expect(find.byKey(const Key('class-0')), findsOneWidget);
      expect(find.byKey(const Key('class-1')), findsOneWidget);
      expect(find.textContaining('No helmet'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2); // key 2 = the second kind
      await tester.pump(const Duration(milliseconds: 100));
      final r = _canvas(tester);
      await tester.dragFrom(r.topLeft + Offset(r.width * .1, r.height * .1), Offset(r.width * .3, r.height * .3));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 150));
      expect(l.saved['h1']!.single[0], 1);
    });

    testWidgets('a save that fails says so and stays on the picture', (tester) async {
      final l = FakeLabeling(saveError: HarvestLabelingException('Could not save: the disk is full.'));
      await _openLabeler(tester, l, 'plate_specialist');
      await _tap(tester, find.byKey(const Key('looks-right')));
      expect(find.text('Could not save: the disk is full.'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(l.saved, isEmpty);
    });

    testWidgets('nothing to check says so, with one button', (tester) async {
      final l = FakeLabeling()..pictures['helmet_specialist'] = const [];
      await _openLabeler(tester, l, 'helmet_specialist');
      expect(find.text('Nothing to check'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('labeler-finish')));
      await _settle(tester);
      expect(find.byKey(const Key('open')), findsOneWidget);
    });
  });

  group('the labeler: zoom, to place a small box exactly', () {
    Future<void> press(WidgetTester tester, LogicalKeyboardKey k, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await tester.sendKeyEvent(k);
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    String level(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('zoom-level'))).data!;

    testWidgets('starts fitted; + and - and the buttons zoom, 0 and the Fit button go back', (tester) async {
      await _openLabeler(tester, FakeLabeling(), 'plate_specialist');
      expect(level(tester), 'Fit');
      final fitted = _shown(tester);

      await press(tester, LogicalKeyboardKey.equal, times: 2);
      expect(level(tester), isNot('Fit'));
      expect(_shown(tester).width, closeTo(fitted.width * 1.25 * 1.25, 1));
      await press(tester, LogicalKeyboardKey.minus);
      expect(_shown(tester).width, closeTo(fitted.width * 1.25, 1));
      await _tap(tester, find.byKey(const Key('zoom-in')));
      expect(_shown(tester).width, closeTo(fitted.width * 1.25 * 1.25, 1));

      await press(tester, LogicalKeyboardKey.digit0);
      expect(level(tester), 'Fit');
      expect(_shown(tester).width, closeTo(fitted.width, 1));
      await press(tester, LogicalKeyboardKey.equal);
      await _tap(tester, find.byKey(const Key('zoom-fit')));
      expect(level(tester), 'Fit');
      expect(_shown(tester).topLeft.dx, closeTo(fitted.topLeft.dx, 1));
    });

    testWidgets('the mouse wheel zooms in on the spot under the pointer; it cannot zoom out past the whole picture', (tester) async {
      await _openLabeler(tester, FakeLabeling(), 'plate_specialist');
      final fitted = _shown(tester);
      final at = fitted.topLeft + Offset(fitted.width * .25, fitted.height * .25);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -300)));
      await tester.pump(const Duration(milliseconds: 50));
      final now = _shown(tester);
      expect(now.width / fitted.width, greaterThan(1.3));
      // the spot that was under the pointer is still under it
      expect(now.left + now.width * .25, closeTo(at.dx, 1.5));
      expect(now.top + now.height * .25, closeTo(at.dy, 1.5));

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 2000)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(level(tester), 'Fit');
    });

    testWidgets('zoomed in, a box too small to draw at normal size can be drawn exactly', (tester) async {
      final l = FakeLabeling();
      await _openLabeler(tester, l, 'plate_specialist');
      await _tap(tester, find.byKey(const Key('nothing-here'))); // a2 has no guess

      await press(tester, LogicalKeyboardKey.equal, times: 12); // stops at the largest zoom
      expect(level(tester), '8.0×');
      final r = _shown(tester);
      await tester.dragFrom(r.center, const Offset(60, 40)); // 60 x 40 pixels, a fraction of a percent of the picture
      await tester.pump(const Duration(milliseconds: 100));
      expect(_enabled(tester, 'looks-right'), isTrue); // at normal size this slip would be thrown away
      await _tap(tester, find.byKey(const Key('looks-right')));
      final box = l.saved['a2']!.single;
      expect(box[1], closeTo(.5 + 30 / r.width, .002));
      expect(box[2], closeTo(.5 + 20 / r.height, .002));
      expect(box[3], closeTo(60 / r.width, .002));
      expect(box[4], closeTo(40 / r.height, .002));
    });

    testWidgets('pulling a corner still lands on the right spot when zoomed', (tester) async {
      final l = FakeLabeling();
      await _openLabeler(tester, l, 'plate_specialist');
      await press(tester, LogicalKeyboardKey.equal); // 1.25x
      final r = _shown(tester);
      await tester.tapAt(r.center); // pick the guessed box (centre .5 .5, size .4 x .3)
      await tester.pump(const Duration(milliseconds: 100));
      final corner = r.topLeft + Offset(r.width * .7, r.height * .65);
      await tester.dragFrom(corner, Offset(r.width * .1, r.height * .15));
      await tester.pump(const Duration(milliseconds: 100));
      await _tap(tester, find.byKey(const Key('looks-right')));
      final fixed = l.saved['a1']!.single; // same answer as without zoom: the corner went to (.8, .8)
      expect(fixed[1], closeTo(.55, .02));
      expect(fixed[3], closeTo(.5, .02));
      expect(fixed[4], closeTo(.45, .02));
    });

    testWidgets('holding Space and dragging moves the zoomed picture and draws nothing', (tester) async {
      await _openLabeler(tester, FakeLabeling(), 'plate_specialist');
      await _tap(tester, find.byKey(const Key('nothing-here'))); // a2 has no guess
      await press(tester, LogicalKeyboardKey.equal, times: 4);
      final before = _shown(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.dragFrom(before.center, const Offset(80, 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 100));
      final after = _shown(tester);
      expect(after.left - before.left, closeTo(80, 1));
      expect(after.top - before.top, closeTo(50, 1));
      expect(_enabled(tester, 'looks-right'), isFalse); // nothing was drawn
    });

    testWidgets('the picture cannot be dragged off its area, and the next picture starts fitted', (tester) async {
      await _openLabeler(tester, FakeLabeling(), 'plate_specialist');
      final fitted = _shown(tester);
      await press(tester, LogicalKeyboardKey.equal, times: 3);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.dragFrom(_shown(tester).center, const Offset(900, 600)); // far more than there is room for
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 100));
      final moved = _shown(tester);
      expect(moved.left, closeTo(fitted.left, 1)); // its left edge stops at the left edge of the area
      expect(moved.top, closeTo(fitted.top, 1));

      await _tap(tester, find.byKey(const Key('looks-right'))); // a1 has a guess: accept, on to a2
      expect(find.text('2 of 3'), findsOneWidget);
      expect(level(tester), 'Fit');
    });
  });

  group('the Harvest tab: only the categories', () {
    Future<void> pump(WidgetTester tester, FakeLabeling l, {String? taskId = 't1', bool active = true}) async {
      await pumpScreen(tester, HarvestCategoriesView(labeling: l, taskId: taskId, active: active), size: const Size(1200, 800));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('one big tile per kind that has pictures, with the number waiting; the empty kind is not shown', (tester) async {
      final l = FakeLabeling();
      await pump(tester, l);
      expect(tester.widget<Text>(find.byKey(const Key('count-plate_specialist'))).data, '3');
      expect(tester.widget<Text>(find.byKey(const Key('count-cabin_specialist'))).data, '2');
      expect(find.byKey(const Key('category-helmet_specialist')), findsNothing);
      expect(find.text('Plates'), findsOneWidget);
      expect(find.text('Cabin'), findsOneWidget);
      expect(l.collects, 0); // already collected
      expect(l.asked.single, 't1');
    });

    testWidgets('an analysis whose pictures were never gathered is gathered once, without asking', (tester) async {
      final l = FakeLabeling(collected: false);
      await pump(tester, l);
      expect(l.collects, 1);
      expect(find.byKey(const Key('category-plate_specialist')), findsOneWidget);
    });

    testWidgets('a protected benchmark clip is never harvested', (tester) async {
      final l = FakeLabeling(collected: false, protectedClip: true);
      await pump(tester, l);
      expect(l.collects, 0);
      expect(find.textContaining('protected'), findsOneWidget);
      expect(find.byKey(const Key('category-plate_specialist')), findsNothing);
    });

    testWidgets('opening a tile opens the labeler; when it closes the numbers are fresh', (tester) async {
      final l = FakeLabeling();
      await pump(tester, l);
      await _tap(tester, find.byKey(const Key('category-plate_specialist')));
      await _settle(tester);
      expect(find.byKey(const Key('labeler-progress')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('looks-right'))); // a1 done
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(tester.widget<Text>(find.byKey(const Key('count-plate_specialist'))).data, '2');
    });

    testWidgets('a finished kind shows a tick and cannot be opened', (tester) async {
      final l = FakeLabeling()..skipped.addAll(['c1', 'c2']);
      await pump(tester, l);
      expect(find.byKey(const Key('count-cabin_specialist')), findsOneWidget);
      expect(tester.widget<Icon>(find.byKey(const Key('count-cabin_specialist'))).icon, Icons.check_circle);
      await tester.tap(find.byKey(const Key('category-cabin_specialist')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('labeler-progress')), findsNothing);
    });

    testWidgets('a helper that will not start is explained, and Try again asks again', (tester) async {
      final l = FakeLabeling(sessionError: HarvestLabelingException('The harvest helper did not start.'));
      await pump(tester, l);
      expect(find.text('The harvest helper did not start.'), findsOneWidget);
      l.sessionError = null;
      await _tap(tester, find.byKey(const Key('harvest-retry')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('category-plate_specialist')), findsOneWidget);
    });

    testWidgets('nothing is asked of the helper until the tab is shown', (tester) async {
      final l = FakeLabeling();
      await pump(tester, l, active: false);
      expect(l.sessions, 0);
      await pumpScreen(tester, HarvestCategoriesView(labeling: l, taskId: 't1'), size: const Size(1200, 800));
      await tester.pump(const Duration(milliseconds: 100));
      expect(l.sessions, 1);
    });

    testWidgets('an analysis with nothing to harvest says so in one line', (tester) async {
      final l = FakeLabeling();
      for (final m in l.pictures.keys) {
        l.pictures[m] = const [];
      }
      await pump(tester, l);
      expect(find.byKey(const Key('harvest-empty')), findsOneWidget);
    });
  });

  testWidgets('the Forensic Analyzer\'s own Harvest tab lists the categories of every analysis', (tester) async {
    final l = FakeLabeling();
    await pumpScreen(
      tester,
      ForensicAnalyzerScreen(
        api: _NoNetworkApi(),
        media: FakeMedia(),
        labeling: l,
        videoBuilder: (context, url, seek, controller) => const SizedBox(),
      ),
      size: const Size(1500, 900),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(l.sessions, 0, reason: 'nothing is asked until the tab is opened');
    await tester.tap(find.text('Harvest').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(l.asked.single, isNull); // no analysis = all of them
    expect(find.byKey(const Key('category-plate_specialist')), findsOneWidget);
  });
}

class _NoNetworkApi extends ForensicApi {
  _NoNetworkApi() : super(baseUrl: 'http://test');

  @override
  Future<ModelChoices> models() async => ModelChoices.empty;

  @override
  Future<List<RunSummary>> history() async => const [];
}
