import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/monitoring/data/camera_api.dart';
import 'package:hulikamote_dashboard/features/monitoring/presentation/widgets/phone_connect_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../forensic/support/test_support.dart';

/// A backend that answers "Connect phone" with the given answers, one per press, and counts the presses.
class _Backend {
  _Backend(this.answers);

  final List<Map<String, dynamic>> answers;
  int asked = 0;

  CameraApi get api => CameraApi(
    baseUrl: 'http://test',
    client: MockClient((req) async {
      expect(req.url.path, '/settings/phone/connect');
      final answer = answers[asked < answers.length ? asked : answers.length - 1];
      asked++;
      return http.Response(jsonEncode(answer), 200);
    }),
  );
}

void main() {
  setUpAll(loadRoboto);

  Future<List<bool?>> open(WidgetTester tester, _Backend backend) async {
    final results = <bool?>[];
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async => results.add(await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => PhoneConnectDialog(api: backend.api))),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));      // the dialog opens
    await tester.pump(const Duration(milliseconds: 400));      // the backend's answer arrives
    return results;
  }

  testWidgets('one click: a found phone is shown for a moment, then the dialog closes by itself with true', (tester) async {
    final backend = _Backend([
      {'ok': true, 'via': 'wifi', 'message': 'Phone found on the same network (192.168.1.77).', 'steps': []},
    ]);
    final results = await open(tester, backend);

    expect(find.text('Phone found on the same network (192.168.1.77).'), findsOneWidget);
    expect(results, isEmpty);                                        // still readable
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(results, [true]);
    expect(find.text('Connect phone'), findsNothing);
    expect(backend.asked, 1);
  });

  testWidgets('a phone that is not found says what to do and what was looked at, and Try again asks once more', (tester) async {
    final backend = _Backend([
      {
        'ok': false,
        'message': 'No phone found. 1) Open HULI-KAMOTE Camera on the phone.',
        'steps': [
          {'text': 'USB tethering / phone hotspot: no phone', 'ok': false},
          {'text': 'Same Wi-Fi network: no phone', 'ok': false},
        ],
      },
      {'ok': true, 'via': 'tethering', 'message': 'Phone found over USB tethering or its hotspot (192.168.42.129).', 'steps': []},
    ]);
    final results = await open(tester, backend);

    expect(find.textContaining('No phone found'), findsOneWidget);
    expect(find.text('Same Wi-Fi network: no phone'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-try-again')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('phone-try-again')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(backend.asked, 2);
    expect(find.textContaining('192.168.42.129'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(results, [true]);
  });

  testWidgets('Cancel closes the dialog with false', (tester) async {
    final backend = _Backend([
      {'ok': false, 'message': 'No phone found.', 'steps': []},
    ]);
    final results = await open(tester, backend);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(results, [false]);
  });
}
