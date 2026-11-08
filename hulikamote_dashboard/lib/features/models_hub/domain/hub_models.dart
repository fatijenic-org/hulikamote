// What the backend's `GET /models/hub` says: every job, its live model and all its versions.

class HubStat {
  const HubStat({required this.key, required this.label, required this.hint});

  final String key, label, hint;

  factory HubStat.fromJson(Map<String, dynamic> j) =>
      HubStat(key: j['key'] as String, label: j['label'] as String, hint: j['hint'] as String? ?? '');
}

/// One type's score on the test photos (car, tricycle, helmet ...).
class HubClass {
  const HubClass({required this.name, required this.score, required this.boxes});

  final String name;
  final double score;
  final int boxes;

  factory HubClass.fromJson(Map<String, dynamic> j) => HubClass(
        name: j['name'] as String,
        score: (j['score'] as num).toDouble(),
        boxes: (j['boxes'] as num?)?.toInt() ?? 0,
      );
}

class HubVersion {
  const HubVersion({
    required this.id,
    required this.name,
    required this.kind,
    required this.origin,
    required this.live,
    required this.usable,
    required this.stats,
    required this.settings,
    this.run,
    this.when,
    this.file,
    this.sizeMb,
    this.bestEpoch,
    this.epochsDone,
    this.epochsPlanned,
    this.classes,
    this.classesSplit,
    this.checking,
    this.passed,
    this.note,
  });

  /// A run folder (`train-3`), a model file name, or a car-matcher file.
  final String id, name, kind, origin;
  final String? run, file, checking, note, classesSplit;
  final bool live, usable;
  final bool? passed;
  final double? when, sizeMb;
  final int? bestEpoch, epochsDone, epochsPlanned;
  final Map<String, double> stats;
  final Map<String, dynamic> settings;
  final List<HubClass>? classes;

  bool get isRun => kind == 'run';

  /// A trained run nobody exported yet: "Use this" prepares it first.
  bool get needsExport => isRun && file == null;

  double? get score => stats['score'];

  factory HubVersion.fromJson(Map<String, dynamic> j) {
    final per = j['classes'] as Map<String, dynamic>?;
    return HubVersion(
      id: j['id'] as String,
      name: j['name'] as String,
      kind: j['kind'] as String,
      origin: j['origin'] as String? ?? 'stock',
      live: j['live'] == true,
      usable: j['usable'] != false,
      run: j['run'] as String?,
      when: (j['when'] as num?)?.toDouble(),
      file: j['file'] as String?,
      sizeMb: (j['size_mb'] as num?)?.toDouble(),
      bestEpoch: (j['best_epoch'] as num?)?.toInt(),
      epochsDone: (j['epochs_done'] as num?)?.toInt(),
      epochsPlanned: (j['epochs_planned'] as num?)?.toInt(),
      stats: {
        for (final e in ((j['stats'] as Map?) ?? const {}).entries)
          if (e.value is num) e.key as String: (e.value as num).toDouble(),
      },
      settings: ((j['settings'] as Map?) ?? const {}).cast<String, dynamic>(),
      classes: per == null ? null : [for (final c in (per['classes'] as List)) HubClass.fromJson((c as Map).cast<String, dynamic>())],
      classesSplit: per?['split'] as String?,
      checking: j['checking'] as String?,
      passed: j['passed'] as bool?,
      note: j['note'] as String?,
    );
  }
}

class HubJob {
  const HubJob({
    required this.job,
    required this.key,
    required this.label,
    required this.kind,
    required this.purpose,
    required this.applies,
    required this.stats,
    required this.scoreFormat,
    required this.canSwitch,
    required this.versions,
    this.liveId,
    this.note,
  });

  /// `vehicles`, `plate`, `helmet`, `cabin`, `reader`, `matcher`, `enhancer`.
  final String job;

  /// The Training Studio's model key (`primary_anchor` ...).
  final String key, label, kind, purpose, applies, scoreFormat;
  final String? liveId, note;
  final bool canSwitch;
  final List<HubStat> stats;
  final List<HubVersion> versions;

  HubVersion? get live => versions.where((v) => v.id == liveId).firstOrNull;

  bool get isDetector => kind == 'yolo';

  factory HubJob.fromJson(Map<String, dynamic> j) => HubJob(
        job: j['job'] as String,
        key: j['key'] as String,
        label: j['label'] as String,
        kind: j['kind'] as String,
        purpose: j['purpose'] as String? ?? '',
        applies: j['applies'] as String? ?? '',
        scoreFormat: j['score_format'] as String? ?? 'decimal',
        canSwitch: j['can_switch'] == true,
        liveId: j['live_id'] as String?,
        note: j['note'] as String?,
        stats: [for (final s in (j['stats'] as List? ?? const [])) HubStat.fromJson((s as Map).cast<String, dynamic>())],
        versions: [for (final v in (j['versions'] as List? ?? const [])) HubVersion.fromJson((v as Map).cast<String, dynamic>())],
      );
}
