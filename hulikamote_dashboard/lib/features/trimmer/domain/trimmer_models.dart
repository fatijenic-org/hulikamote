/// What the backend knows about a video (length, speed, size).
class ProbeInfo {
  const ProbeInfo({required this.duration, required this.fps, required this.width, required this.height});

  final double duration;
  final double fps;
  final int width;
  final int height;

  factory ProbeInfo.fromJson(Map<String, dynamic> json) => ProbeInfo(
        duration: (json['duration'] as num).toDouble(),
        fps: (json['fps'] as num?)?.toDouble() ?? 25,
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );
}

enum JobStatus {
  queued('Waiting'),
  running('Cutting'),
  done('Done'),
  failed('Failed'),
  cancelled('Cancelled');

  const JobStatus(this.label);

  final String label;

  static JobStatus parse(String? text) => values.firstWhere((s) => s.name == text, orElse: () => JobStatus.failed);
}

/// One clip being cut (or waiting to be, or finished) on the laptop.
class TrimJob {
  const TrimJob({
    required this.id,
    required this.source,
    required this.output,
    required this.start,
    required this.end,
    required this.label,
    required this.status,
    this.progress = 0,
    this.error = '',
    this.exact = false,
  });

  final String id;
  final String source;
  final String output;
  final double start;
  final double end;
  final String label;
  final JobStatus status;
  final double progress;
  final String error;
  final bool exact;

  bool get active => status == JobStatus.queued || status == JobStatus.running;

  /// The file's own name, without the folder.
  String get outputName => output.split(RegExp(r'[\\/]')).last;

  factory TrimJob.fromJson(Map<String, dynamic> json) => TrimJob(
        id: json['id'] as String,
        source: json['source'] as String? ?? '',
        output: json['output'] as String? ?? '',
        start: (json['start'] as num?)?.toDouble() ?? 0,
        end: (json['end'] as num?)?.toDouble() ?? 0,
        label: json['label'] as String? ?? '',
        status: JobStatus.parse(json['status'] as String?),
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        error: json['error'] as String? ?? '',
        exact: json['exact'] as bool? ?? false,
      );
}

/// A clip as it is sent to be cut.
class ClipRequest {
  const ClipRequest({required this.start, required this.end, this.label = ''});

  final double start;
  final double end;
  final String label;

  Map<String, dynamic> toJson() => {'start': start, 'end': end, 'label': label};
}

/// What the backend answered when a benchmark export started.
class BenchStart {
  const BenchStart({required this.jobs, this.skipped = const [], this.folder = '', this.needsZone = const [], this.clipIds = const []});

  final List<TrimJob> jobs;

  /// The names the new clips get in the benchmark registry (what scoring is asked for).
  final List<String> clipIds;
  final List<String> skipped;
  final String folder;

  /// Violations in these clips that judge a drawn zone: the clip needs its zone drawn in the Forensic Analyzer before it is scored.
  final List<String> needsZone;
}

/// One row of the benchmark folder statistics: what the folder of one violation holds.
class BenchStat {
  const BenchStat({required this.violation, this.clips = 0, this.events = 0, this.seconds = 0, this.plates = 0, this.cleanClips = 0, this.need = 10});

  final String violation;
  final int clips;
  final int events;
  final double seconds;

  /// Events that have a typed true plate.
  final int plates;

  /// Clean clips judged for this violation.
  final int cleanClips;

  /// Events a verdict needs.
  final int need;

  factory BenchStat.fromJson(Map<String, dynamic> j) => BenchStat(
        violation: '${j['violation']}',
        clips: (j['clips'] as num?)?.toInt() ?? 0,
        events: (j['events'] as num?)?.toInt() ?? 0,
        seconds: (j['seconds'] as num?)?.toDouble() ?? 0,
        plates: (j['plates'] as num?)?.toInt() ?? 0,
        cleanClips: (j['clean_clips'] as num?)?.toInt() ?? 0,
        need: (j['need'] as num?)?.toInt() ?? 10,
      );
}

/// The whole benchmark folder: a row per violation, and the totals.
class BenchStats {
  const BenchStats({this.rows = const [], this.clips = 0, this.seconds = 0, this.missing = 0});

  final List<BenchStat> rows;
  final int clips;
  final double seconds;

  /// Clips in the list whose video file is not on the disk.
  final int missing;

  factory BenchStats.fromJson(Map<String, dynamic> j) {
    final t = Map<String, dynamic>.from((j['total'] as Map?) ?? const {});
    return BenchStats(
      rows: [for (final r in (j['rows'] as List? ?? const [])) BenchStat.fromJson(Map<String, dynamic>.from(r as Map))],
      clips: (t['clips'] as num?)?.toInt() ?? 0,
      seconds: (t['seconds'] as num?)?.toDouble() ?? 0,
      missing: (t['missing'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The file the player should open for a video (see [TrimmerApi.preview]).
class TrimPreview {
  const TrimPreview({required this.state, required this.path, this.progress = 0, this.error = '', this.copy = false});

  final String state; // ready | working | failed
  final String path;
  final double progress;
  final String error;

  /// True when [path] is a small copy, not the video itself.
  final bool copy;
}

/// A saved setup of the Live Monitor / Forensic Analyzer: the zones, signs and settings drawn for one camera view.
class SavedSetup {
  const SavedSetup({required this.id, required this.name, required this.violations, this.updated = 0});

  final String id;
  final String name;
  final List<String> violations;
  final double updated;

  factory SavedSetup.fromJson(Map<String, dynamic> j) => SavedSetup(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        violations: [for (final v in (j['violations'] as List? ?? const [])) '$v'],
        updated: (j['updated'] as num?)?.toDouble() ?? 0,
      );
}
