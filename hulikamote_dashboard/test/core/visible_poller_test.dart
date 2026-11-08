import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/core/utils/visible_poller.dart';

class _Probe extends StatefulWidget {
  const _Probe({required this.poller});
  final VisiblePoller poller;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.poller.attach(context);
  }

  @override
  void dispose() {
    widget.poller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Widget _page(VisiblePoller poller, {required bool shown}) => MaterialApp(
      home: TickerMode(enabled: shown, child: _Probe(poller: poller)),
    );

void main() {
  testWidgets('ticks while the page is shown and stops when another page takes over', (tester) async {
    var ticks = 0;
    final poller = VisiblePoller(interval: const Duration(seconds: 2), onTick: () => ticks++);

    await tester.pumpWidget(_page(poller, shown: true));
    expect(ticks, 1); // right away
    await tester.pump(const Duration(seconds: 6));
    expect(ticks, 4);

    await tester.pumpWidget(_page(poller, shown: false)); // the shell switched to another tab
    final atHide = ticks;
    await tester.pump(const Duration(seconds: 20));
    expect(ticks, atHide, reason: 'a hidden page must not poll');
    expect(poller.running, isFalse);

    await tester.pumpWidget(_page(poller, shown: true)); // back again
    expect(ticks, atHide + 1, reason: 'catches up at once');
    await tester.pump(const Duration(seconds: 2));
    expect(ticks, atHide + 2);
  });

  testWidgets('can be switched off and on, and starts switched off when asked', (tester) async {
    var ticks = 0;
    final poller = VisiblePoller(interval: const Duration(seconds: 1), onTick: () => ticks++, initiallyActive: false);
    await tester.pumpWidget(_page(poller, shown: true));
    await tester.pump(const Duration(seconds: 5));
    expect(ticks, 0);

    poller.active = true;
    await tester.pump(const Duration(seconds: 3));
    expect(ticks, 4); // one at once + three ticks

    poller.active = false;
    final stopped = ticks;
    await tester.pump(const Duration(seconds: 5));
    expect(ticks, stopped);
  });

  testWidgets('never starts a tick while the previous one is still running', (tester) async {
    var started = 0;
    final gate = Completer<void>();
    final poller = VisiblePoller(
      interval: const Duration(seconds: 1),
      onTick: () {
        started++;
        return gate.future; // a backend that is slow to answer
      },
    );
    await tester.pumpWidget(_page(poller, shown: true));
    await tester.pump(const Duration(seconds: 10));
    expect(started, 1);

    gate.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(started, 2);
  });

  testWidgets('a failing tick does not stop the polling', (tester) async {
    var ticks = 0;
    final poller = VisiblePoller(
      interval: const Duration(seconds: 1),
      onTick: () async {
        ticks++;
        throw Exception('backend down');
      },
    );
    await tester.pumpWidget(_page(poller, shown: true));
    await tester.pump(const Duration(seconds: 3));
    expect(ticks, 4);
  });
}
