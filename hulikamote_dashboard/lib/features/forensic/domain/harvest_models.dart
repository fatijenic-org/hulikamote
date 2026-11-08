/// What the Harvest tab shows: the pictures the Training Lab collected from analyses, grouped by
/// the model they teach. Read from `training_lab/harvest_inbox/gallery.json`, which the harvest
/// tool writes (see `training_lab/harvest_tool/gallery.py`). Pure Dart: no Flutter, no files.
library;

/// Where one picture is in the harvest loop (the tool's own states).
enum HarvestState {
  check('Needs checking', 'The model drew a box. Confirm it or fix it.'),
  label('Needs a box', 'The model found nothing here. Draw the box, or say there is nothing to box.'),
  ready('Checked', 'You decided. It waits to be added to the dataset.'),
  skipped('Skipped', 'You were not sure, so it stays out of training.'),
  accepted('Added', 'Part of the training dataset now.');

  const HarvestState(this.title, this.explain);

  final String title;
  final String explain;

  bool get needsEyes => this == check || this == label;

  static HarvestState fromName(Object? name) {
    for (final s in values) {
      if (s.name == '$name') return s;
    }
    return check;
  }
}

class HarvestBox {
  const HarvestBox({required this.cls, required this.cx, required this.cy, required this.w, required this.h});

  final int cls;
  final double cx, cy, w, h;

  /// `[class, cx, cy, w, h]`, normalised to the picture (YOLO format).
  static HarvestBox? fromJson(Object? j) {
    if (j is! List || j.length < 5) return null;
    double d(int i) => (j[i] as num).toDouble();
    return HarvestBox(cls: (j[0] as num).toInt(), cx: d(1), cy: d(2), w: d(3), h: d(4));
  }
}

class HarvestItem {
  const HarvestItem({
    required this.id,
    required this.image,
    required this.state,
    required this.source,
    required this.why,
    required this.reason,
    required this.violation,
    required this.suggested,
    required this.boxes,
    required this.width,
    required this.height,
    required this.group,
    required this.task,
    required this.ticket,
    required this.created,
    required this.decided,
    required this.accepted,
    required this.datasetName,
  });

  final String id;

  /// Path of the picture relative to the inbox folder.
  final String image;
  final HarvestState state;
  final String source;

  /// One short line: why this picture is here.
  final String why;

  /// The full question the check & label page asks about it.
  final String reason;
  final String? violation;

  /// The boxes are the model's suggestion (before a human decided).
  final bool suggested;
  final List<HarvestBox> boxes;
  final int width, height;
  final String group;
  final String? task, ticket;
  final DateTime? created, decided, accepted;
  final String? datasetName;

  factory HarvestItem.fromJson(Map<String, dynamic> j) => HarvestItem(
        id: '${j['id']}',
        image: '${j['image']}',
        state: HarvestState.fromName(j['state']),
        source: '${j['source'] ?? ''}',
        why: '${j['why'] ?? ''}',
        reason: '${j['reason'] ?? ''}',
        violation: j['violation'] as String?,
        suggested: j['suggested'] == true,
        boxes: [for (final b in ((j['boxes'] as List?) ?? const [])) ?HarvestBox.fromJson(b)],
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
        group: '${j['group'] ?? ''}',
        task: j['task'] as String?,
        ticket: j['ticket'] as String?,
        created: _time(j['created']),
        decided: _time(j['decided']),
        accepted: _time(j['accepted']),
        datasetName: j['dataset_name'] as String?,
      );

  double get aspect => (width > 0 && height > 0) ? width / height : 4 / 3;
}

class HarvestCounts {
  const HarvestCounts({
    this.check = 0,
    this.label = 0,
    this.ready = 0,
    this.skipped = 0,
    this.accepted = 0,
  });

  final int check, label, ready, skipped, accepted;

  int get needsEyes => check + label;
  int get total => check + label + ready + skipped + accepted;

  int of(HarvestState s) => switch (s) {
        HarvestState.check => check,
        HarvestState.label => label,
        HarvestState.ready => ready,
        HarvestState.skipped => skipped,
        HarvestState.accepted => accepted,
      };

  factory HarvestCounts.fromJson(Map<String, dynamic>? j) {
    int n(String k) => (j?[k] as num?)?.toInt() ?? 0;
    return HarvestCounts(
      check: n('check'),
      label: n('label'),
      ready: n('ready'),
      skipped: n('skipped'),
      accepted: n('accepted'),
    );
  }
}

class HarvestClass {
  const HarvestClass(this.name, this.help);

  final String name, help;
}

/// A plate picture the OCR learns from; the plate text is part of its file name.
class HarvestSample {
  const HarvestSample({required this.path, required this.label, required this.when});

  /// Relative to the Training Lab folder.
  final String path;
  final String label;
  final DateTime? when;
}

/// The photos of one car (for the car matcher).
class HarvestGroup {
  const HarvestGroup({required this.id, required this.n, required this.photos});

  final String id;
  final int n;
  final List<String> photos;
}

/// One use: a model the harvest feeds, or data the app collects by itself.
class HarvestCategory {
  const HarvestCategory({
    required this.key,
    required this.isDetector,
    required this.title,
    required this.does,
    required this.usedFor,
    required this.fedBy,
    required this.yourJob,
    required this.violations,
    required this.classes,
    required this.modelFile,
    required this.training,
    required this.datasetImages,
    required this.counts,
    required this.next,
    required this.sources,
    required this.violationsSeen,
    required this.items,
    required this.how,
    required this.count,
    required this.need,
    required this.unit,
    required this.samples,
    required this.groups,
    required this.facts,
  });

  final String key;

  /// A detection model the check & label page feeds (plate, helmet, cabin);
  /// otherwise data the app collects by itself (OCR, car matcher).
  final bool isDetector;
  final String title, does, usedFor, yourJob, next;
  final List<String> fedBy, violations;
  final List<HarvestClass> classes;
  final String? modelFile;

  /// null = unknown (not checked when the snapshot was made).
  final bool? training;
  final int datasetImages;
  final HarvestCounts counts;
  final List<({String key, String label, int n})> sources;
  final List<({String violation, int n})> violationsSeen;
  final List<HarvestItem> items;

  // automatic data
  final String how;
  final int count, need;
  final String unit;
  final List<HarvestSample> samples;
  final List<HarvestGroup> groups;
  final List<({String label, int value})> facts;

  /// Pictures of this use (detectors: everything in the inbox; automatic: the folder's count).
  int get pictures => isDetector ? counts.total : count;

  /// 0..1 towards the amount that makes a retrain worthwhile (automatic data only).
  double get progress => need <= 0 ? 1 : (count / need).clamp(0.0, 1.0);

  factory HarvestCategory.fromJson(Map<String, dynamic> j) {
    List<String> strings(Object? v) => [for (final e in ((v as List?) ?? const [])) '$e'];
    List<Map<String, dynamic>> maps(Object? v) =>
        [for (final e in ((v as List?) ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
    return HarvestCategory(
      key: '${j['key']}',
      isDetector: j['kind'] != 'automatic',
      title: '${j['title'] ?? j['key']}',
      does: '${j['does'] ?? ''}',
      usedFor: '${j['used_for'] ?? ''}',
      fedBy: strings(j['fed_by']),
      yourJob: '${j['your_job'] ?? ''}',
      violations: strings(j['violations']),
      classes: [for (final c in maps(j['classes'])) HarvestClass('${c['name']}', '${c['help'] ?? ''}')],
      modelFile: j['model_file'] as String?,
      training: j['training'] as bool?,
      datasetImages: (j['dataset_images'] as num?)?.toInt() ?? 0,
      counts: HarvestCounts.fromJson((j['counts'] as Map?)?.cast<String, dynamic>()),
      next: '${j['next'] ?? ''}',
      sources: [
        for (final s in maps(j['sources']))
          (key: '${s['key']}', label: '${s['label'] ?? s['key']}', n: (s['n'] as num?)?.toInt() ?? 0),
      ],
      violationsSeen: [
        for (final v in maps(j['violations_seen'])) (violation: '${v['violation']}', n: (v['n'] as num?)?.toInt() ?? 0),
      ],
      items: [for (final i in maps(j['items'])) HarvestItem.fromJson(i)],
      how: '${j['how'] ?? ''}',
      count: (j['count'] as num?)?.toInt() ?? 0,
      need: (j['need'] as num?)?.toInt() ?? 0,
      unit: '${j['unit'] ?? 'pictures'}',
      samples: [
        for (final s in maps(j['samples']))
          HarvestSample(path: '${s['path']}', label: '${s['label'] ?? ''}', when: _time(s['when'])),
      ],
      groups: [
        for (final g in maps(j['groups']))
          HarvestGroup(
            id: '${g['id']}',
            n: (g['n'] as num?)?.toInt() ?? 0,
            photos: [for (final p in ((g['photos'] as List?) ?? const [])) '$p'],
          ),
      ],
      facts: [
        for (final f in maps(j['facts'])) (label: '${f['label']}', value: (f['value'] as num?)?.toInt() ?? 0),
      ],
    );
  }
}

class HarvestGallery {
  const HarvestGallery({
    required this.generated,
    required this.lab,
    required this.inbox,
    required this.protectedClips,
    required this.categories,
  });

  final DateTime? generated;

  /// Absolute folders, as the tool saw them.
  final String lab, inbox;

  /// Benchmark clips that are never harvested.
  final int protectedClips;
  final List<HarvestCategory> categories;

  static const int schema = 1;

  List<HarvestCategory> get detectors => [for (final c in categories) if (c.isDetector) c];

  /// Pictures waiting for a human, across every detector.
  int get needEyes => detectors.fold(0, (a, c) => a + c.counts.needsEyes);
  int get ready => detectors.fold(0, (a, c) => a + c.counts.ready);
  int get added => detectors.fold(0, (a, c) => a + c.counts.accepted);
  int get total => detectors.fold(0, (a, c) => a + c.counts.total);

  HarvestCategory? byKey(String? key) {
    for (final c in categories) {
      if (c.key == key) return c;
    }
    return null;
  }

  factory HarvestGallery.fromJson(Map<String, dynamic> j) => HarvestGallery(
        generated: _time(j['generated']),
        lab: '${j['lab'] ?? ''}',
        inbox: '${j['inbox'] ?? ''}',
        protectedClips: (j['protected'] as num?)?.toInt() ?? 0,
        categories: [
          for (final c in ((j['categories'] as List?) ?? const []))
            if (c is Map) HarvestCategory.fromJson(Map<String, dynamic>.from(c)),
        ],
      );
}

DateTime? _time(Object? seconds) {
  if (seconds is! num || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}

/// Colours of the boxes, one per class index (the same as the check & label page).
const List<int> harvestBoxColors = [0xFF2F9E44, 0xFFE03131, 0xFF1971C2, 0xFFF08C00, 0xFF9C36B5, 0xFF0C8599];
