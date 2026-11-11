import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/screens/live_monitoring_screen.dart';

const backendDown = 'The backend is not answering. Restart it, then press Try again.';

MockClient answering() => MockClient((req) async => http.Response('{"source_url": "C:/clips/street_cam.mp4"}', 200));

Future<void> pumpAt(WidgetTester tester, Size size, {http.Client? client}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: LiveMonitoringScreen(client: client ?? answering())));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('starts paused with one clear Start button (nothing connects until it is pressed)', (tester) async {
    await pumpAt(tester, const Size(1400, 800));
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Monitoring is off'), findsOneWidget);
    expect(find.text('Start monitoring'), findsOneWidget);          // one primary action, not two
    expect(find.text('Stop monitoring'), findsNothing);
    expect(find.text('Live detections'), findsOneWidget);
    expect(find.text('No detections yet'), findsOneWidget);
  });

  testWidgets('"Detect road" is offered only while the video plays (there is no frame to freeze while paused)', (tester) async {
    await pumpAt(tester, const Size(1400, 800));
    expect(find.byKey(const ValueKey('road-detect-toggle')), findsNothing);
    expect(find.text('Detect road'), findsNothing);
  });

  testWidgets('"Change source" offers a camera or phone and a video file in one place', (tester) async {
    await pumpAt(tester, const Size(1400, 800));
    expect(find.text('Camera or phone…'), findsNothing);
    await tester.tap(find.text('Change source'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Camera or phone…'), findsOneWidget);
    expect(find.text('Video file…'), findsOneWidget);
  });

  testWidgets('the demo switch is tucked in the More menu', (tester) async {
    await pumpAt(tester, const Size(1400, 800));
    expect(find.text('Simulate violations (demo)'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Simulate violations (demo)'), findsOneWidget);
  });

  testWidgets('a narrow window stacks the picture above the detections without overflowing', (tester) async {
    await pumpAt(tester, const Size(760, 900));
    expect(tester.takeException(), isNull);
    final stage = tester.getTopLeft(find.text('Monitoring is off')).dy;
    final side = tester.getTopLeft(find.text('Live detections')).dy;
    expect(side, greaterThan(stage));                               // below, not beside
  });

  testWidgets('the detections panel can be folded away and brought back', (tester) async {
    await pumpAt(tester, const Size(1400, 800));
    final stageWide = tester.getSize(find.text('Monitoring is off')).width;
    expect(find.text('Live detections'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide detections'));
    await tester.pump();
    expect(find.text('Live detections'), findsNothing);
    expect(find.byTooltip('Show detections'), findsOneWidget);
    await tester.tap(find.byTooltip('Show detections'));
    await tester.pump();
    expect(find.text('Live detections'), findsOneWidget);
    expect(tester.getSize(find.text('Monitoring is off')).width, stageWide);
  });

  group('knowing whether it works', () {
    testWidgets('a backend that answers shows its source and no warning', (tester) async {
      await pumpAt(tester, const Size(1400, 800));
      expect(find.text('street_cam.mp4'), findsWidgets);            // the file the backend really uses
      expect(find.text(backendDown), findsNothing);
    });

    testWidgets('a backend that does not answer is named at once, not after an endless wait', (tester) async {
      await pumpAt(tester, const Size(1400, 800), client: MockClient((req) async => throw Exception('no answer')));
      expect(find.text(backendDown), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('Start does not pretend to run when the backend is down', (tester) async {
      await pumpAt(tester, const Size(1400, 800), client: MockClient((req) async => http.Response('', 500)));
      await tester.tap(find.text('Start monitoring'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Monitoring is off'), findsOneWidget);       // still paused
      expect(find.text('Stop monitoring'), findsNothing);
      expect(find.text(backendDown), findsOneWidget);
    });

    testWidgets('a missing video relay is named, and Start does not pretend to run', (tester) async {
      final client = MockClient((req) async => req.url.path == '/settings/video-server'
          ? http.Response('{"ready": false, "message": "The video relay (MediaMTX) is not running."}', 200)
          : http.Response('{"source_url": "cam.mp4"}', 200));
      await pumpAt(tester, const Size(1400, 800), client: client);
      expect(find.textContaining('The video relay (MediaMTX) is not running.'), findsOneWidget);
      await tester.tap(find.text('Start monitoring'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Monitoring is off'), findsOneWidget);
      expect(find.text('Stop monitoring'), findsNothing);
    });

    testWidgets('an older backend that cannot be asked about the relay is not blamed', (tester) async {
      final client = MockClient((req) async => req.url.path == '/settings/video-server' ? http.Response('{"detail":"Not Found"}', 404) : http.Response('{"source_url": "cam.mp4"}', 200));
      await pumpAt(tester, const Size(1400, 800), client: client);
      expect(find.text(backendDown), findsNothing);
      expect(find.textContaining('relay'), findsNothing);
    });

    testWidgets('Try again clears the warning once the backend is back', (tester) async {
      var up = false;
      final client = MockClient((req) async => up ? http.Response('{"source_url": "cam.mp4"}', 200) : throw Exception('down'));
      await pumpAt(tester, const Size(1400, 800), client: client);
      expect(find.text(backendDown), findsOneWidget);
      up = true;
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(backendDown), findsNothing);
    });
  });
}
