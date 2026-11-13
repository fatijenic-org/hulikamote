import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/ban_hours.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/review_controller.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/decision_panel.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/queue_panel.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/video_time_card.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/violation_params.dart';

import 'support/test_support.dart';

/// The truck ban depends on the hour: the hours the operator sets, the time of the video (found or typed), and the time on each ticket.

const _rush = [
  ['06:00', '09:00'],
  ['16:00', '19:00'],
];

/// A backend that answers the time of a video from a script and remembers what it was asked.
class FakeClockApi extends ForensicApi {
  FakeClockApi(this.answer) : super(baseUrl: 'http://test');

  VideoClock? Function(String typed, double trim) answer;
  final List<({String path, String typed, double trim})> asked = [];
  Object? fail;

  @override
  Future<VideoClock?> videoClock(String videoPath, {String videoStart = '', double trimStart = 0}) async {
    asked.add((path: videoPath, typed: videoStart, trim: trimStart));
    if (fail != null) throw fail!;
    return answer(videoStart, trimStart);
  }
}

VideoClock found(DateTime start, {String source = 'screen', String label = 'read from the clock in the picture', String note = ''}) =>
    VideoClock(start: start, source: source, label: label, confirmed: true, note: note);

VideoClock notFound([String? daylight = 'day']) => VideoClock(source: 'estimate', note: 'No time was found in the video.', daylight: daylight);

AnalysisDraft draftWithVideo() {
  final d = AnalysisDraft()..chooseVideo(path: 'C:/videos/street.mp4', name: 'street.mp4');
  d.toggle('truck_ban', on: true);
  return d;
}

Future<void> pumpCard(WidgetTester tester, AnalysisDraft draft, ForensicApi api) => tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: VideoTimeCard(key: UniqueKey(), draft: draft, api: api, typingPause: const Duration(milliseconds: 20)),
        ),
      ),
    ));

Future<void> pumpParams(WidgetTester tester, AnalysisDraft draft, String key) => tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: ViolationParams(draft: draft, violationKey: key, onChanged: () => setState(() {})),
          ),
        ),
      ),
    ));

void main() {
  setUpAll(loadRoboto);

  group('BanHours', () {
    test('reads and says times of day', () {
      expect(BanHours.minutes('06:00'), 360);
      expect(BanHours.minutes('6'), 360);
      expect(BanHours.minutes('23:30'), 1410);
      expect(BanHours.minutes('24:00'), 1440);
      for (final bad in ['', 'abc', '25:00', '6:99', '24:30', null]) {
        expect(BanHours.minutes(bad), isNull, reason: '$bad');
      }
      expect(BanHours.label('06:00'), '6:00 AM');
      expect(BanHours.label('16:30'), '4:30 PM');
      expect(BanHours.label('00:00'), '12:00 AM');
      expect(BanHours.label('12:00'), '12:00 PM');
      expect(BanHours.clock(DateTime(2026, 11, 5, 7, 42)), '7:42 AM');
    });

    test('offers every half hour of the day', () {
      expect(BanHours.options.length, 48);
      expect(BanHours.options.first, '00:00');
      expect(BanHours.options.last, '23:30');
    });

    test('says whether a moment is inside the hours: the start counts, the end does not, and a window can pass midnight', () {
      bool at(int h, int m, List raw) => BanHours.contains(raw, DateTime(2026, 11, 5, h, m));
      expect(at(6, 0, _rush), isTrue);
      expect(at(8, 59, _rush), isTrue);
      expect(at(9, 0, _rush), isFalse);
      expect(at(12, 0, _rush), isFalse);
      expect(at(18, 59, _rush), isTrue);
      expect(at(23, 0, const [['22:00', '05:00']]), isTrue);
      expect(at(2, 0, const [['22:00', '05:00']]), isTrue);
      expect(at(5, 0, const [['22:00', '05:00']]), isFalse);
    });

    test('drops windows that cannot be used and describes the rest in words', () {
      expect(BanHours.describe(_rush), '6:00 AM–9:00 AM and 4:00 PM–7:00 PM');
      expect(BanHours.describe(const [['06:00', '06:00'], ['x', '09:00'], ['07:00']]), '');
      expect(BanHours.describe(null), '');
    });
  });

  group('what goes to the backend', () {
    test('a typed start time and the file name travel with the run, a blank one does not', () {
      final d = draftWithVideo();
      expect(d.buildConfig().containsKey('video_start'), isFalse);
      expect(d.buildConfig()['video_name'], 'street.mp4');
      d.settings.videoStart = '  7:30 AM ';
      expect(d.buildConfig()['video_start'], '7:30 AM');
    });

    test('the hours of the truck ban travel in its own settings', () {
      final d = draftWithVideo();
      d.config('truck_ban')['ban_windows'] = _rush;
      expect(((d.buildConfig()['per_violation_configs'] as Map)['truck_ban'] as Map)['ban_windows'], _rush);
    });

    test('a start time typed for one video is not kept for the next one', () {
      final d = draftWithVideo();
      d.settings.videoStart = '7:30';
      d.chooseVideo(path: 'C:/videos/other.mp4', name: 'other.mp4');
      expect(d.settings.videoStart, '');
      d.settings.videoStart = '8:00';
      d.reset();
      expect(d.settings.videoStart, '');
    });
  });

  group('the hours editor (Settings of the truck ban)', () {
    testWidgets('starts off: the ban holds all day', (tester) async {
      final d = AnalysisDraft();
      await pumpParams(tester, d, 'truck_ban');
      expect(tester.widget<Switch>(find.byKey(const ValueKey('ban-hours-switch'))).value, isFalse);
      expect(find.textContaining('Off: the ban holds all day'), findsOneWidget);
      expect(find.byKey(const ValueKey('ban-hours-from-0')), findsNothing);
      expect(d.config('truck_ban')['ban_windows'], isNull);
      expect(find.text('Truck'), findsOneWidget); // the vehicle types are still there
    });

    testWidgets('turning it on gives a first window, turning it off clears them', (tester) async {
      final d = AnalysisDraft();
      await pumpParams(tester, d, 'truck_ban');
      await tester.tap(find.byKey(const ValueKey('ban-hours-switch')));
      await tester.pump();
      expect(d.config('truck_ban')['ban_windows'], [
        ['06:00', '09:00'],
      ]);
      expect(find.byKey(const ValueKey('ban-hours-from-0')), findsOneWidget);
      expect(find.textContaining('The example is only an example'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ban-hours-switch')));
      await tester.pump();
      expect(d.config('truck_ban')['ban_windows'], isEmpty);
      expect(find.byKey(const ValueKey('ban-hours-from-0')), findsNothing);
    });

    testWidgets('the example button puts in both rush hours', (tester) async {
      final d = AnalysisDraft();
      await pumpParams(tester, d, 'truck_ban');
      await tester.tap(find.byKey(const ValueKey('ban-hours-switch')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ban-hours-example')));
      await tester.pump();
      expect(d.config('truck_ban')['ban_windows'], _rush);
      expect(find.byKey(const ValueKey('ban-hours-from-1')), findsOneWidget);
    });

    testWidgets('a start or an end is picked from the half hours', (tester) async {
      final d = AnalysisDraft();
      await pumpParams(tester, d, 'truck_ban');
      await tester.tap(find.byKey(const ValueKey('ban-hours-switch')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('ban-hours-to-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10:30 AM').last);
      await tester.pumpAndSettle();
      expect(d.config('truck_ban')['ban_windows'], [
        ['06:00', '10:30'],
      ]);
      expect(find.text('10:30 AM'), findsOneWidget);
    });

    testWidgets('hours can be added up to three and removed again', (tester) async {
      final d = AnalysisDraft();
      await pumpParams(tester, d, 'truck_ban');
      await tester.tap(find.byKey(const ValueKey('ban-hours-switch')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('ban-hours-add')));
      await tester.pump();
      expect(d.config('truck_ban')['ban_windows'], [
        ['06:00', '09:00'],
        ['09:00', '10:00'], // the next window starts where the last one ended, an hour long
      ]);
      await tester.tap(find.byKey(const ValueKey('ban-hours-add')));
      await tester.pump();
      expect((d.config('truck_ban')['ban_windows'] as List).length, 3);
      expect(find.byKey(const ValueKey('ban-hours-add')), findsNothing); // three is the most

      await tester.tap(find.byKey(const ValueKey('ban-hours-remove-1')));
      await tester.pump();
      expect((d.config('truck_ban')['ban_windows'] as List).length, 2);
      expect(find.byKey(const ValueKey('ban-hours-add')), findsOneWidget);
    });

    testWidgets('only the truck ban has hours', (tester) async {
      final d = AnalysisDraft();
      await pumpParams(tester, d, 'tricycle_on_highway');
      expect(find.byKey(const ValueKey('ban-hours-switch')), findsNothing);
    });
  });

  group('the time of the video card', () {
    testWidgets('shows the time it found, where it came from, and whether the video starts inside the ban hours', (tester) async {
      final d = draftWithVideo()..config('truck_ban')['ban_windows'] = _rush;
      final api = FakeClockApi((typed, trim) => found(DateTime(2026, 11, 5, 7, 42), note: 'Two readings agree.'));
      await pumpCard(tester, d, api);
      expect(find.byKey(const ValueKey('video-time-busy')), findsOneWidget);
      await tester.pump();
      await tester.pump();
      expect(find.text('7:42 AM'), findsOneWidget);
      expect(find.text('read from the clock in the picture'), findsOneWidget);
      expect(find.text('Two readings agree.'), findsOneWidget);
      expect(find.text('Ban hours: 6:00 AM–9:00 AM and 4:00 PM–7:00 PM. This video starts inside them.'), findsOneWidget);
      expect(api.asked.single.path, 'C:/videos/street.mp4');
      expect(api.asked.single.typed, '');
    });

    testWidgets('says "outside" for a video that starts outside the ban hours', (tester) async {
      final d = draftWithVideo()..config('truck_ban')['ban_windows'] = _rush;
      await pumpCard(tester, d, FakeClockApi((t, _) => found(DateTime(2026, 11, 5, 13, 5))));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('This video starts outside them.'), findsOneWidget);
    });

    testWidgets('says nothing about hours when none are set', (tester) async {
      final d = draftWithVideo();
      await pumpCard(tester, d, FakeClockApi((t, _) => found(DateTime(2026, 11, 5, 7, 42))));
      await tester.pump();
      await tester.pump();
      expect(find.text('7:42 AM'), findsOneWidget);
      expect(find.byKey(const ValueKey('video-time-verdict')), findsNothing);
    });

    testWidgets('when no time is found it says so with what the picture looks like, and what happens next', (tester) async {
      final d = draftWithVideo();
      await pumpCard(tester, d, FakeClockApi((t, _) => notFound('night')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('video-time-none')), findsOneWidget);
      expect(find.text('No time found in the video'), findsOneWidget);
      expect(find.textContaining('The picture looks like night.'), findsOneWidget);
      expect(find.textContaining('"time not confirmed"'), findsOneWidget);
    });

    testWidgets('typing a start time asks again with it, after a short pause, and shows the typed time', (tester) async {
      final d = draftWithVideo()..config('truck_ban')['ban_windows'] = _rush;
      final api = FakeClockApi((typed, trim) =>
          typed.isEmpty ? notFound() : found(DateTime(2026, 11, 5, 7, 30), source: 'operator', label: 'typed by the operator'));
      await pumpCard(tester, d, api);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('video-time-none')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('video-start-field')), '7:30');
      expect(d.settings.videoStart, '7:30'); // kept at once for the run
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      await tester.pump();
      expect(api.asked.last.typed, '7:30');
      expect(find.text('7:30 AM'), findsOneWidget);
      expect(find.text('typed by the operator'), findsOneWidget);
      expect(find.textContaining('This video starts inside them.'), findsOneWidget);
    });

    testWidgets('a quick typist causes one question, not one per letter', (tester) async {
      final d = draftWithVideo();
      final api = FakeClockApi((t, _) => notFound());
      await pumpCard(tester, d, api);
      await tester.pump();
      await tester.pump();
      final before = api.asked.length;
      for (final text in ['7', '7:', '7:3', '7:30']) {
        await tester.enterText(find.byKey(const ValueKey('video-start-field')), text);
        await tester.pump(const Duration(milliseconds: 5));
      }
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(api.asked.length - before, 1);
      expect(api.asked.last.typed, '7:30');
    });

    testWidgets('the clear button goes back to finding the time in the video', (tester) async {
      final d = draftWithVideo()..settings.videoStart = '7:30';
      final api = FakeClockApi((typed, trim) => typed.isEmpty ? notFound() : found(DateTime(2026, 11, 5, 7, 30), source: 'operator'));
      await pumpCard(tester, d, api);
      await tester.pump();
      await tester.pump();
      expect(find.text('7:30 AM'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('video-start-clear')));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      await tester.pump();
      expect(d.settings.videoStart, '');
      expect(api.asked.last.typed, '');
      expect(find.byKey(const ValueKey('video-time-none')), findsOneWidget);
    });

    testWidgets('moving the start of the trim asks again for the new start', (tester) async {
      final d = draftWithVideo();
      d.setFrame(url: '/f.jpg', seconds: 0, fps: 25, frames: 1000, duration: 40);
      final api = FakeClockApi((typed, trim) => found(DateTime(2026, 11, 5, 7, 40).add(Duration(seconds: trim.round()))));
      await pumpCard(tester, d, api);
      await tester.pump();
      await tester.pump();
      expect(find.text('7:40 AM'), findsOneWidget);
      d.setTrim(start: 30);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(api.asked.last.trim, 30);
      expect(find.text('7:40 AM'), findsOneWidget); // 7:40:30
    });

    testWidgets('an old backend and a failing one are explained, not swallowed', (tester) async {
      final d = draftWithVideo();
      await pumpCard(tester, d, FakeClockApi((t, _) => null));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('video-time-unsupported')), findsOneWidget);

      final failing = FakeClockApi((t, _) => notFound())..fail = Exception('The backend is not answering.');
      await pumpCard(tester, d, failing);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('The backend is not answering.'), findsOneWidget);
    });
  });

  group('the ForensicApi call', () {
    ForensicApi api(Future<http.Response> Function(http.Request) h) => ForensicApi(baseUrl: 'http://test', client: MockClient(h));

    test('asks by path with what was typed and the trim, and reads the answer', () async {
      late Uri seen;
      final clock = await api((req) async {
        seen = req.url;
        return http.Response(
          jsonEncode({'start': '2026-11-05T07:40:00', 'source': 'screen', 'label': 'read from the clock in the picture', 'confirmed': true, 'note': 'n', 'daylight': null}),
          200,
        );
      }).videoClock('C:/videos/my clip.mp4', videoStart: ' 7:40 ', trimStart: 12.5);
      expect(seen.path, '/api/forensic/video-clock');
      expect(seen.queryParameters, {'file_path': 'C:/videos/my clip.mp4', 'video_start': '7:40', 'trim_start': '12.5'});
      expect(clock!.start, DateTime(2026, 11, 5, 7, 40));
      expect(clock.source, 'screen');
      expect(clock.confirmed, isTrue);
    });

    test('leaves out what was not typed and what is zero', () async {
      late Uri seen;
      await api((req) async {
        seen = req.url;
        return http.Response(jsonEncode({'start': null, 'source': 'none', 'confirmed': false}), 200);
      }).videoClock('C:/v.mp4');
      expect(seen.queryParameters, {'file_path': 'C:/v.mp4'});
    });

    test('no time found is a clock with no start', () async {
      final clock = await api((req) async => http.Response(jsonEncode({'start': null, 'source': 'estimate', 'confirmed': false, 'daylight': 'day', 'note': 'No time was found in the video.'}), 200))
          .videoClock('C:/v.mp4');
      expect(clock!.start, isNull);
      expect(clock.confirmed, isFalse);
      expect(clock.daylight, 'day');
    });

    test('an old backend gives null, a refusal gives its reason', () async {
      expect(await api((req) async => http.Response('{"detail":"Not Found"}', 404)).videoClock('C:/v.mp4'), isNull);
      await expectLater(
        api((req) async => http.Response('{"detail":"That video was not found"}', 404)).videoClock('C:/v.mp4'),
        throwsA(predicate((e) => '$e'.contains('That video was not found'))),
      );
    });
  });

  group('the time on a ticket', () {
    Map<String, dynamic> withTime(Map<String, dynamic> time, {List<Map<String, dynamic>> flags = const []}) =>
        {...ticketJson(1, violations: ['truck_ban'], vclass: 'truck'), 'time': time, 'flags': flags};

    test('is read from the report', () {
      final t = ForensicTicket.fromJson(withTime({
        'at': '2026-11-05T07:42:10',
        'source': 'screen',
        'label': 'read from the clock in the picture',
        'confirmed': true,
      }));
      expect(t.time!.at, DateTime(2026, 11, 5, 7, 42, 10));
      expect(t.time!.short, '7:42 AM');
      expect(t.time!.long, '7:42 AM (read from the clock in the picture)');
      expect(t.time!.needsCheck, isFalse);
      expect(ForensicTicket.fromJson(ticketJson(2)).time, isNull); // older reports have none
    });

    test('says "not confirmed" when the hour matters and the time is not known', () {
      final t = ForensicTicket.fromJson(withTime({'at': null, 'source': 'estimate', 'confirmed': false, 'needs_check': true, 'note': 'No time was found in the video.'}));
      expect(t.time!.at, isNull);
      expect(t.time!.needsCheck, isTrue);
      expect(t.time!.short, 'time not confirmed');
      expect(t.time!.long, 'Time not confirmed');
    });

    test('the flag has its own plain title', () {
      expect(const TicketFlag(type: 'time_unconfirmed').title, 'Time not confirmed');
    });

    testWidgets('the queue shows when it happened next to where it is in the video', (tester) async {
      final ticket = ForensicTicket.fromJson(withTime({'at': '2026-11-05T07:42:10', 'source': 'screen', 'label': 'x', 'confirmed': true}));
      final c = ReviewController(gateway: FakeGateway(), taskId: 'task', tickets: [ticket]);
      await pumpScreen(
        tester,
        TicketTile(ticket: ticket, status: ReviewStatus.pending, selected: false, media: FakeMedia(), onTap: () {}),
        size: const Size(700, 300),
      );
      expect(find.textContaining('7:42 AM'), findsOneWidget);
      expect(c.all.length, 1);
    });

    testWidgets('the open ticket says when it happened and where the time came from', (tester) async {
      final ticket = ForensicTicket.fromJson(
        withTime({'at': '2026-11-05T07:42:10', 'source': 'screen', 'label': 'read from the clock in the picture', 'confirmed': true}),
      );
      await pumpScreen(tester, _panel(ticket), size: const Size(500, 1400));
      expect(find.byKey(const ValueKey('ticket-time')), findsOneWidget);
      expect(find.text('7:42 AM (read from the clock in the picture)'), findsOneWidget);
    });

    testWidgets('an unconfirmed time is said clearly on the open ticket', (tester) async {
      final ticket = ForensicTicket.fromJson(withTime(
        {'at': null, 'source': 'estimate', 'confirmed': false, 'needs_check': true, 'note': 'No time was found in the video.'},
        flags: [
          {'type': 'time_unconfirmed', 'detail': 'No time was found in the video. This rule only holds at certain hours: check the time before confirming.'},
        ],
      ));
      await pumpScreen(tester, _panel(ticket), size: const Size(500, 1400));
      expect(find.byKey(const ValueKey('ticket-time')), findsOneWidget);
      expect(find.text('Time not confirmed'), findsWidgets); // the line under the labels, and the flag's title
    });

    testWidgets('a ticket of a video whose time was not looked for shows no time line', (tester) async {
      await pumpScreen(tester, _panel(ForensicTicket.fromJson(ticketJson(1, violations: ['truck_ban'], vclass: 'truck'))), size: const Size(500, 1400));
      expect(find.byKey(const ValueKey('ticket-time')), findsNothing);
    });
  });
}

Widget _panel(ForensicTicket ticket) {
  final c = ReviewController(gateway: FakeGateway(), taskId: 'task', tickets: [ticket]);
  return DecisionPanel(controller: c, media: FakeMedia(), onDecide: (_) {}, onMerge: () {}, plateFocus: FocusNode());
}
