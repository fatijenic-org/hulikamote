import '../../forensic/domain/violation_catalog.dart';

double? _num(dynamic v) => (v as num?)?.toDouble();
int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// Seconds as short text: 3.0 -> "3", 12.5 -> "12.5".
String secondsText(num? v) {
  if (v == null) return '';
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// "42%" for a 0..1 ratio, "-" when there is nothing to divide.
String percentText(double? v) => v == null ? '-' : '${(v * 100).round()}%';

/// One thing that REALLY happens in a clip. Times stay text while editing ("12.5" or "1:05"); the backend reads them.
class BenchEvent {
  BenchEvent({required this.violation, this.start = '', this.end = '', this.plate = ''});

  String violation;
  String start;
  String end;
  String plate;

  factory BenchEvent.fromJson(Map<String, dynamic> j) => BenchEvent(
        violation: '${j['violation']}',
        start: secondsText(_num(j['start'])),
        end: secondsText(_num(j['end'])),
        plate: '${j['plate'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {'violation': violation, 'start': start, 'end': end, 'plate': plate};
}

class BenchClip {
  const BenchClip({
    required this.id,
    required this.note,
    required this.clean,
    required this.fileOk,
    required this.settingsOk,
    required this.enabled,
    required this.seconds,
    required this.events,
  });

  final String id;
  final String note;
  final bool clean;
  final bool fileOk;
  final bool settingsOk;
  final List<String> enabled; // violations switched on in the run this clip came from: only these are judged
  final double? seconds;
  final List<BenchEvent> events;

  factory BenchClip.fromJson(Map<String, dynamic> j) => BenchClip(
        id: '${j['id']}',
        note: '${j['note'] ?? ''}',
        clean: j['clean'] == true,
        fileOk: j['file_ok'] != false,
        settingsOk: j['settings_ok'] != false,
        enabled: [for (final k in (j['enabled'] as List? ?? const [])) '$k'],
        seconds: _num(j['seconds']),
        events: [
          for (final e in (j['events'] as List? ?? const [])) BenchEvent.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );
}

/// How far one violation is from having enough real events to be scored.
class CoverageRow {
  const CoverageRow({required this.key, required this.events, required this.clips, required this.needed, required this.state});

  final String key;
  final int events;
  final int clips;
  final int needed;
  final String state;

  bool get ready => events >= needed;

  factory CoverageRow.fromJson(Map<String, dynamic> j) => CoverageRow(
        key: '${j['key']}',
        events: _int(j['events']),
        clips: _int(j['clips']),
        needed: _int(j['needed']),
        state: '${j['state']}',
      );
}

class ReportBrief {
  const ReportBrief({
    required this.name,
    required this.label,
    required this.created,
    required this.caught,
    required this.falseAlarms,
    required this.missed,
    required this.precision,
    required this.recall,
  });

  final String name;
  final String label;
  final String created;
  final int caught;
  final int falseAlarms;
  final int missed;
  final double? precision;
  final double? recall;

  factory ReportBrief.fromJson(Map<String, dynamic> j) => ReportBrief(
        name: '${j['name']}',
        label: '${j['label']}',
        created: '${j['created'] ?? ''}',
        caught: _int(j['caught']),
        falseAlarms: _int(j['false_alarms']),
        missed: _int(j['missed']),
        precision: _num(j['precision']),
        recall: _num(j['recall']),
      );

  /// "baseline  ·  2026-10-26 14:05"
  String get title {
    final when = created.replaceFirst('T', ' ');
    return when.isEmpty ? label : '$label  ·  ${when.length > 16 ? when.substring(0, 16) : when}';
  }
}

/// A benchmark that is running (or ran last), as the backend reports it.
class RunProgress {
  const RunProgress({
    required this.id,
    required this.status,
    required this.label,
    required this.clipsTotal,
    required this.clipsDone,
    required this.current,
    required this.stage,
    required this.error,
    required this.report,
    required this.results,
  });

  final String id;
  final String status; // running | done | failed | cancelled
  final String label;
  final int clipsTotal;
  final int clipsDone;
  final String? current;
  final String stage;
  final String? error;
  final String? report; // the saved report's name once done
  final List<Map<String, dynamic>> results;

  bool get running => status == 'running';
  double get fraction => clipsTotal == 0 ? 0 : clipsDone / clipsTotal;

  factory RunProgress.fromJson(Map<String, dynamic> j) => RunProgress(
        id: '${j['id']}',
        status: '${j['status']}',
        label: '${j['label'] ?? ''}',
        clipsTotal: _int(j['clips_total']),
        clipsDone: _int(j['clips_done']),
        current: j['current'] as String?,
        stage: '${j['stage'] ?? ''}',
        error: j['error'] as String?,
        report: j['report'] as String?,
        results: [for (final r in (j['results'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)],
      );
}

class BenchOverview {
  const BenchOverview({
    required this.minEvents,
    required this.passPrecision,
    required this.passRecall,
    required this.rows,
    required this.clips,
    required this.problems,
    required this.reports,
    required this.run,
  });

  final int minEvents;
  final double passPrecision;
  final double passRecall;
  final List<CoverageRow> rows;
  final List<BenchClip> clips;
  final List<String> problems;
  final List<ReportBrief> reports;
  final RunProgress? run;

  double get totalSeconds => clips.fold(0.0, (a, c) => a + (c.seconds ?? 0));

  /// The same overview with a fresher run status (progress polling).
  BenchOverview withRun(RunProgress? r) => BenchOverview(
        minEvents: minEvents,
        passPrecision: passPrecision,
        passRecall: passRecall,
        rows: rows,
        clips: clips,
        problems: problems,
        reports: reports,
        run: r,
      );

  factory BenchOverview.fromJson(Map<String, dynamic> j) {
    final defaults = Map<String, dynamic>.from(j['defaults'] as Map? ?? const {});
    final pass = Map<String, dynamic>.from(defaults['pass'] as Map? ?? const {});
    Map<String, dynamic> m(dynamic x) => Map<String, dynamic>.from(x as Map);
    return BenchOverview(
      minEvents: _int(defaults['min_events']),
      passPrecision: _num(pass['precision']) ?? 0.8,
      passRecall: _num(pass['recall']) ?? 0.8,
      rows: [for (final r in (j['violations'] as List? ?? const [])) CoverageRow.fromJson(m(r))],
      clips: [for (final c in (j['clips'] as List? ?? const [])) BenchClip.fromJson(m(c))],
      problems: [for (final p in (j['problems'] as List? ?? const [])) '$p'],
      reports: [for (final r in (j['reports'] as List? ?? const [])) ReportBrief.fromJson(m(r))],
      run: j['run'] == null ? null : RunProgress.fromJson(m(j['run'])),
    );
  }
}

/// What a past forensic run flagged: a starting point for the events, to confirm by watching the clip.
class RunSuggestion {
  const RunSuggestion({required this.violation, required this.track, required this.start, required this.end, required this.plate});

  final String violation;
  final dynamic track;
  final double? start;
  final double? end;
  final String? plate;

  factory RunSuggestion.fromJson(Map<String, dynamic> j) => RunSuggestion(
        violation: '${j['violation']}',
        track: j['track'],
        start: _num(j['start']),
        end: _num(j['end']),
        plate: j['plate'] as String?,
      );

  BenchEvent toEvent() => BenchEvent(violation: violation, start: secondsText(start), end: secondsText(end), plate: plate ?? '');
}

class RunSuggestions {
  const RunSuggestions({required this.enabled, required this.videoKept, required this.suggestions});

  final List<String> enabled;
  final bool videoKept;
  final List<RunSuggestion> suggestions;

  factory RunSuggestions.fromJson(Map<String, dynamic> j) => RunSuggestions(
        enabled: [for (final k in (j['enabled'] as List? ?? const [])) '$k'],
        videoKept: j['video_kept'] == true,
        suggestions: [
          for (final s in (j['suggestions'] as List? ?? const [])) RunSuggestion.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
      );
}

/// One violation's row of a report.
class ViolationScore {
  const ViolationScore({
    required this.key,
    required this.clips,
    required this.events,
    required this.caught,
    required this.falseAlarms,
    required this.missed,
    required this.precision,
    required this.recall,
    required this.f1,
    required this.loar,
    required this.status,
  });

  final String key;
  final int clips;
  final int events;
  final int caught;
  final int falseAlarms;
  final int missed;
  final double? precision;
  final double? recall;
  final double? f1;
  final double? loar;
  final String status;

  /// "PASS" / "FAIL" once there are enough real events; otherwise why not.
  bool get pass => status == 'PASS';
  bool get fail => status == 'FAIL';

  factory ViolationScore.fromJson(String key, Map<String, dynamic> j) {
    final plates = Map<String, dynamic>.from(j['plates'] as Map? ?? const {});
    return ViolationScore(
      key: key,
      clips: _int(j['clips']),
      events: _int(j['events']),
      caught: _int(j['caught']),
      falseAlarms: _int(j['false_alarms']),
      missed: _int(j['missed']),
      precision: _num(j['precision']),
      recall: _num(j['recall']),
      f1: _num(j['f1']),
      loar: _num(plates['loar']),
      status: '${j['status']}',
    );
  }
}

/// A saved report, ready to show.
class ReportDetail {
  const ReportDetail({
    required this.label,
    required this.created,
    required this.overall,
    required this.scores,
    required this.notBenchmarked,
    required this.clips,
    required this.passPrecision,
    required this.passRecall,
    required this.minEvents,
  });

  final String label;
  final String created;
  final Map<String, dynamic> overall;
  final List<ViolationScore> scores;
  final List<String> notBenchmarked;
  final List<Map<String, dynamic>> clips; // clip_id, caught / missed / false_alarms lists
  final double passPrecision;
  final double passRecall;
  final int minEvents;

  factory ReportDetail.fromJson(Map<String, dynamic> j) {
    final summary = Map<String, dynamic>.from(j['summary'] as Map? ?? const {});
    final defaults = Map<String, dynamic>.from(j['defaults'] as Map? ?? const {});
    final pass = Map<String, dynamic>.from(defaults['pass'] as Map? ?? const {});
    final order = [for (final v in ViolationCatalog.all) v.key];
    final keys = [...order.where(summary.containsKey), ...summary.keys.where((k) => !order.contains(k))];
    return ReportDetail(
      label: '${j['label']}',
      created: '${j['created'] ?? ''}',
      overall: Map<String, dynamic>.from(j['overall'] as Map? ?? const {}),
      scores: [for (final k in keys) ViolationScore.fromJson(k, Map<String, dynamic>.from(summary[k] as Map))],
      notBenchmarked: [for (final k in (j['not_benchmarked'] as List? ?? const [])) '$k'],
      clips: [for (final c in (j['clips'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)],
      passPrecision: _num(pass['precision']) ?? 0.8,
      passRecall: _num(pass['recall']) ?? 0.8,
      minEvents: _int(defaults['min_events']),
    );
  }
}
