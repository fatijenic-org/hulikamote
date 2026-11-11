import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/features/models_hub/presentation/widgets/training_log_card.dart';

import '../forensic/support/test_support.dart';

/// A backend that answers the log call and counts how often it was asked.
class Log {
  Log({this.file = 'bbbb.log', this.logs = 'Epoch 4/40  box_loss 1.2', this.training = true});

  String? file;
  String logs;
  bool training;
  int asked = 0;
  String? askedFor;

  late final http.Client client = MockClient((req) async {
    asked++;
    askedFor = req.url.path;
    return http.Response(
      jsonEncode({'model': 'primary_anchor', 'file': file, 'logs': logs, 'truncated': false, 'training': training, 'updated': 1793000000.0}),
      200,
    );
  });
}

Future<void> pump(WidgetTester tester, Log log, {int signal = 0}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: TrainingLogCard(modelKey: 'primary_anchor', client: log.client, openSignal: signal)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(loadRoboto);

  testWidgets('a model that was never trained shows nothing', (tester) async {
    await pump(tester, Log(file: null, logs: '', training: false));
    expect(find.text('Training log'), findsNothing);
    await done(tester);
  });

  testWidgets('it asks for this model\'s log, and the log opens only when asked for', (tester) async {
    final log = Log();
    await pump(tester, log);
    expect(log.askedFor, '/api/train/log/model/primary_anchor');
    expect(find.text('Training log'), findsOneWidget);
    expect(find.text('Training now'), findsOneWidget);
    expect(find.textContaining('box_loss'), findsNothing);
    await tester.tap(find.text('Training log'));
    await tester.pump();
    expect(find.textContaining('Epoch 4/40'), findsOneWidget);
    await done(tester);
  });

  testWidgets('Continue opens it (the page raises the signal)', (tester) async {
    final log = Log();
    await pump(tester, log);
    expect(find.textContaining('Epoch 4/40'), findsNothing);
    await pump(tester, log, signal: 1);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Epoch 4/40'), findsOneWidget);
    await done(tester);
  });

  testWidgets('open and training, it follows the log; closed, it does not ask again', (tester) async {
    final log = Log();
    await pump(tester, log);
    final closed = log.asked;
    await tester.pump(const Duration(seconds: 10));
    expect(log.asked, closed); // closed: no polling

    await tester.tap(find.text('Training log'));
    await tester.pump();
    final opened = log.asked;
    log.logs = 'Epoch 5/40  box_loss 1.1';
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 50));
    expect(log.asked, greaterThan(opened));
    expect(find.textContaining('Epoch 5/40'), findsOneWidget);

    log.training = false; // the run ended: it stops asking
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 50));
    final ended = log.asked;
    await tester.pump(const Duration(seconds: 10));
    expect(log.asked, ended);
    expect(find.text('Training now'), findsNothing);
    await done(tester);
  });
}
