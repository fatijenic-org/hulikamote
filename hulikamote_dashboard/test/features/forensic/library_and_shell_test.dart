import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/screens/forensic_analyzer_screen.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/library_view.dart';

import 'support/test_support.dart';

/// A backend with a small library, no network.
class LibraryApi extends ForensicApi {
  LibraryApi({this.runs = const [], this.failHistory = false}) : super(baseUrl: 'http://test');

  List<RunSummary> runs;
  bool failHistory;
  int historyCalls = 0;
  final List<String> openedReports = [];
  final List<String> sentToLive = [];
  Map<String, ReviewStatus> saved = {};

  /// What the status endpoint answers (a finished run with three tickets unless a test sets it).
  RunStatus Function()? onStatus;

  @override
  Future<RunStatus> status(String taskId, {bool tickets = false}) async =>
      onStatus?.call() ?? RunStatus(status: 'completed', progress: 100, tickets: sampleTickets(3));

  @override
  Future<List<RunSummary>> history() async {
    historyCalls++;
    if (failHistory) throw ForensicApiException('The backend is not running.');
    return runs;
  }

  @override
  Future<Map<String, dynamic>> runConfig(String taskId) async => {
        'active_violations': taskId.startsWith('a') ? ['counterflow', 'red_light', 'no_helmet'] : ['swerving'],
      };

  @override
  Future<List<ForensicTicket>> report(String reportUrl) async {
    openedReports.add(reportUrl);
    return sampleTickets(5);
  }

  @override
  Future<Map<String, ReviewStatus>> savedStatuses(Set<String> dbIds, {int maxPages = 8}) async => {
        for (final e in saved.entries)
          if (dbIds.contains(e.key)) e.key: e.value,
      };

  @override
  Future<ModelChoices> models() async => ModelChoices.empty;

  @override
  Future<String> sendToLive(String taskId) async {
    sentToLive.add(taskId);
    return 'Sent to the Live Monitor.';
  }

  @override
  Future<void> setStatus(List<String> dbIds, ReviewStatus status) async {}
}

RunSummary _run(String id, DateTime at,
        {int tickets = 5, String? video = '/v.mp4', bool early = false, bool running = false}) =>
    RunSummary(
        taskId: id,
        createdAt: at,
        ticketCount: tickets,
        videoUrl: video,
        reportUrl: '/$id/report.json',
        stoppedEarly: early,
        running: running);

void main() {
  setUpAll(loadRoboto);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 9, 30);
  final yesterday = today.subtract(const Duration(days: 1));
  final lastWeek = today.subtract(const Duration(days: 7));

  group('formatting', () {
    test('formatRunTime uses a 12-hour clock', () {
      expect(formatRunTime(DateTime(2026, 10, 6, 14, 2)), 'Oct 6, 2026 · 2:02 PM');
      expect(formatRunTime(DateTime(2026, 1, 3, 0, 5)), 'Jan 3, 2026 · 12:05 AM');
      expect(formatRunTime(DateTime(2026, 1, 3, 12, 0)), 'Jan 3, 2026 · 12:00 PM');
    });

    test('dayLabel says Today and Yesterday, then the date', () {
      final n = DateTime(2026, 10, 13, 18, 0);
      expect(dayLabel(DateTime(2026, 10, 13, 1), n), 'Today');
      expect(dayLabel(DateTime(2026, 10, 12, 23), n), 'Yesterday');
      expect(dayLabel(DateTime(2026, 10, 1, 8), n), 'Oct 1, 2026');
    });
  });

  group('library', () {
    Future<LibraryApi> pump(WidgetTester tester, LibraryApi api,
        {void Function(RunSummary)? onOpen, VoidCallback? onNew, Future<void> Function(String)? onLive}) async {
      await pumpScreen(
        tester,
        LibraryView(
          api: api,
          onOpen: onOpen ?? (_) {},
          onSendToLive: onLive ?? (_) async {},
          onNew: onNew ?? () {},
        ),
        size: const Size(1300, 800),
      );
      await tester.pump(const Duration(milliseconds: 50)); // history
      await tester.pump(const Duration(milliseconds: 50)); // run settings
      return api;
    }

    testWidgets('groups runs by day and shows what each one found', (tester) async {
      final api = LibraryApi(runs: [
        _run('aaaa1111-0', today, tickets: 24),
        _run('bbbb2222-0', yesterday, tickets: 1),
        _run('cccc3333-0', lastWeek, tickets: 0, video: null),
      ]);
      await pump(tester, api);

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('3 analyses'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text('24 tickets'), findsOneWidget);
      expect(find.text('1 ticket'), findsOneWidget); // singular
      expect(find.text('0 tickets'), findsOneWidget);
      expect(find.text('Video ready'), findsNWidgets(2));
      expect(find.text('No video'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a run that was cut short with "Stop here" says so on its card; the others do not', (tester) async {
      final api = LibraryApi(runs: [_run('aaaa1111-0', today, early: true), _run('bbbb2222-0', yesterday)]);
      await pump(tester, api);
      expect(find.text('Stopped early'), findsOneWidget);
      expect(find.byKey(const Key('stopped-early-aaaa1111-0')), findsOneWidget);
      expect(RunSummary.fromJson({'task_id': 'x', 'created_at': 1, 'report_url': '/r', 'stopped_early': true}).stoppedEarly, isTrue);
      expect(RunSummary.fromJson({'task_id': 'x', 'created_at': 1, 'report_url': '/r'}).stoppedEarly, isFalse);
    });

    testWidgets('a run that is still going says so on its card instead of "Video ready"', (tester) async {
      final api = LibraryApi(runs: [_run('aaaa1111-0', today, running: true, video: null), _run('bbbb2222-0', yesterday)]);
      await pump(tester, api);
      expect(find.byKey(const Key('running-aaaa1111-0')), findsOneWidget);
      expect(find.text('Analyzing'), findsOneWidget);
      expect(find.text('Video ready'), findsOneWidget); // only the finished one
      expect(find.byKey(const Key('running-bbbb2222-0')), findsNothing);
    });

    testWidgets('each card names the violations it looked for', (tester) async {
      final api = LibraryApi(runs: [_run('aaaa1111-0', today), _run('bbbb2222-0', yesterday)]);
      await pump(tester, api);
      expect(find.text('Counterflow'), findsOneWidget); // first of three, the rest folded
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('Swerving'), findsOneWidget);
    });

    testWidgets('opening a card hands over that run', (tester) async {
      RunSummary? opened;
      final api = LibraryApi(runs: [_run('aaaa1111-0', today), _run('bbbb2222-0', yesterday)]);
      await pump(tester, api, onOpen: (r) => opened = r);
      await tester.tap(find.text('Swerving')); // inside the second card
      await tester.pump();
      expect(opened?.taskId, 'bbbb2222-0');
    });

    testWidgets('a run can be sent to the Live Monitor from its menu', (tester) async {
      final sent = <String>[];
      final api = LibraryApi(runs: [_run('aaaa1111-0', today)]);
      await pump(tester, api, onLive: (id) async => sent.add(id));
      await tester.tap(find.byTooltip('More'));
      await tester.pump(); // the menu route
      await tester.pump(const Duration(milliseconds: 500)); // and its opening animation
      await tester.tap(find.text('Send to Live Monitor'));
      await tester.pump();
      expect(sent, ['aaaa1111-0']);
    });

    testWidgets('an empty library points at the first analysis', (tester) async {
      var newTaps = 0;
      await pump(tester, LibraryApi(), onNew: () => newTaps++);
      expect(find.text('No analyses yet'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'New analysis'));
      expect(newTaps, 1);
    });

    testWidgets('a backend that is down shows why and can be retried', (tester) async {
      final api = LibraryApi(failHistory: true);
      await pump(tester, api);
      expect(find.text('Could not load the library'), findsOneWidget);
      expect(find.text('The backend is not running.'), findsOneWidget);

      api
        ..failHistory = false
        ..runs = [_run('aaaa1111-0', today)];
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Could not load the library'), findsNothing);
      expect(find.text('1 analysis'), findsOneWidget);
    });
  });

  group('screen', () {
    Future<LibraryApi> pump(WidgetTester tester, LibraryApi api, {Size size = const Size(1500, 900)}) async {
      await pumpScreen(
        tester,
        ForensicAnalyzerScreen(
          api: api,
          media: FakeMedia(),
          videoBuilder: (context, url, seek, controller) => Center(child: Text('VIDEO $url')),
        ),
        size: size,
      );
      await tester.pump(const Duration(milliseconds: 100));
      return api;
    }

    testWidgets('starts on the new-analysis wizard and keeps the library one click away', (tester) async {
      await pump(tester, LibraryApi(runs: [_run('aaaa1111-0', today)]));
      expect(find.text('Forensic Analyzer'), findsOneWidget);
      expect(find.text('Choose a video to analyze'), findsOneWidget);
      expect(find.widgetWithText(SegmentedButton<int>, 'New analysis'), findsOneWidget);

      await tester.tap(find.text('Library'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1 analysis'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening a run loads its tickets and decisions made earlier', (tester) async {
      final api = LibraryApi(runs: [_run('aaaa1111-0', today)]);
      // ticket 1's rows were confirmed in an earlier session
      api.saved = {'db1a': ReviewStatus.confirmed, 'db1b': ReviewStatus.confirmed};
      await pump(tester, api);
      await tester.tap(find.text('Library'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Counterflow'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.openedReports, ['/aaaa1111-0/report.json']);
      expect(find.textContaining('Photos'), findsWidgets); // the workspace is up
      expect(find.byTooltip('Back to the library'), findsOneWidget);
      expect(find.textContaining('1 of 5'), findsWidgets); // earlier decision counted as reviewed
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening a run that is still going shows its tickets so far and follows it to the end', (tester) async {
      final api = LibraryApi(runs: [_run('aaaa1111-0', today, running: true, video: null, tickets: 2)]);
      api.onStatus = () => RunStatus(status: 'processing', progress: 30, ticketCount: 2, tickets: sampleTickets(2));
      await pump(tester, api);
      await tester.tap(find.text('Library'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Counterflow'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.openedReports, isEmpty); // it follows the run; the finished report is not there yet
      expect(find.byKey(const Key('still-analyzing')), findsOneWidget);
      expect(find.textContaining('30%'), findsWidgets);
      expect(find.textContaining('0 of 2'), findsWidgets);

      // the run ends: two more tickets, the video exists, the banner goes away
      api.onStatus = () => RunStatus(
          status: 'completed', progress: 100, resultVideo: '/v.mp4', ticketCount: 4, tickets: sampleTickets(4));
      await tester.pump(const Duration(seconds: 4)); // the follow timer
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('still-analyzing')), findsNothing);
      expect(find.textContaining('0 of 4'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('back from a run returns to the library with the list refreshed', (tester) async {
      final api = LibraryApi(runs: [_run('aaaa1111-0', today)]);
      await pump(tester, api);
      await tester.tap(find.text('Library'));
      await tester.pump(const Duration(milliseconds: 100));
      final callsBefore = api.historyCalls;

      await tester.tap(find.text('Counterflow'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.byTooltip('Back to the library'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Library'), findsWidgets);
      expect(find.text('1 analysis'), findsOneWidget);
      expect(api.historyCalls, greaterThan(callsBefore));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a report that cannot be opened is explained, not a blank page', (tester) async {
      final api = _BrokenReportApi(runs: [_run('aaaa1111-0', today)]);
      await pump(tester, api);
      await tester.tap(find.text('Library'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Counterflow'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.textContaining('Could not open that analysis'), findsOneWidget);
      expect(find.text('Forensic Analyzer'), findsOneWidget); // still on the page
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(find.textContaining('Could not open that analysis'), findsNothing);
    });
  });
}

class _BrokenReportApi extends LibraryApi {
  _BrokenReportApi({super.runs});

  @override
  Future<List<ForensicTicket>> report(String reportUrl) async => throw ForensicApiException('Loading the report failed (HTTP 404).');
}
