/// What the Harvest tab and the full-screen labeler talk about: one analysis (or all of them) and the pictures a person
/// still has to look at. Read from the harvest tool's local helper (`harvest.py serve`). Pure Dart.
library;

import 'harvest_models.dart';

/// "rider_with_helmet" -> "With helmet": the class names of the datasets, in words a person would use.
String friendlyClass(String name) {
  const known = {
    'license_plate': 'Plate',
    'rider_with_helmet': 'Helmet on',
    'rider_without_helmet': 'No helmet',
    'clear_window': 'Windshield',
    'tinted_window': 'Dark windshield',
    'seatbelt': 'Seatbelt',
    'driver_phone': 'Phone',
    'side_mirror': 'Mirror',
    'person': 'Rider',
  };
  final hit = known[name];
  if (hit != null) return hit;
  final words = name.replaceAll('_', ' ').trim();
  return words.isEmpty ? name : words[0].toUpperCase() + words.substring(1);
}

/// One thing the harvest can teach (the plate finder, the helmet check, the cabin check) and how much of it waits.
class LabelModelInfo {
  const LabelModelInfo({
    required this.key,
    required this.title,
    required this.classes,
    required this.help,
    required this.counts,
  });

  final String key;
  final String title;
  final List<String> classes;
  final Map<String, String> help;
  final HarvestCounts counts;

  int get toCheck => counts.needsEyes;

  /// "Plates", "Helmets", "Cabin": the word on the tile.
  String get tileName => switch (key) {
        'plate_specialist' => 'Plates',
        'helmet_specialist' => 'Helmets',
        'cabin_specialist' => 'Cabin',
        'primary_anchor' => 'Vehicles',
        _ => title,
      };

  /// The one question the labeler asks, in a few words.
  String get ask => switch (key) {
        'plate_specialist' => 'Box the plate. No plate? Press Nothing here.',
        'helmet_specialist' => 'Box each rider: helmet on, or no helmet.',
        'cabin_specialist' => 'Box what you can see.',
        'primary_anchor' => 'Box every vehicle and rider. Fix the guess.',
        _ => 'Check the boxes.',
      };

  factory LabelModelInfo.fromJson(Map<String, dynamic> j) => LabelModelInfo(
        key: '${j['key']}',
        title: '${j['title'] ?? j['key']}',
        classes: [for (final c in ((j['classes'] as List?) ?? const [])) '$c'],
        help: {for (final e in ((j['help'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        counts: HarvestCounts.fromJson((j['counts'] as Map?)?.cast<String, dynamic>()),
      );
}

/// The harvest of one analysis (`task` set) or of every analysis (`task` null).
class LabelSession {
  const LabelSession({
    required this.task,
    required this.collected,
    required this.protected,
    required this.collecting,
    required this.collectError,
    required this.models,
    this.pairs = const PairCounts(),
    this.cars = const CarCounts(),
    this.hasVideo,
  });

  final String? task;

  /// The ticketed cars of this analysis whose photos can be walked along (nothing for "every analysis").
  final CarCounts cars;

  /// The "same car?" questions of this analysis (or of all of them).
  final PairCounts pairs;

  /// The analysis kept its video, so frames of the clip itself can be harvested (null = not asked: every analysis).
  final bool? hasVideo;

  /// Its pictures were gathered from the analysis already (always true for "every analysis").
  final bool collected;

  /// A benchmark clip: it is never harvested.
  final bool protected;
  final bool collecting;
  final String? collectError;
  final List<LabelModelInfo> models;

  /// The categories that have any picture for this analysis.
  List<LabelModelInfo> get categories => [for (final m in models) if (m.counts.total > 0) m];

  factory LabelSession.fromJson(Map<String, dynamic> j) {
    final collect = Map<String, dynamic>.from((j['collect'] as Map?) ?? const {});
    return LabelSession(
      task: j['task'] as String?,
      collected: j['collected'] != false,
      protected: j['protected'] == true,
      collecting: collect['running'] == true,
      collectError: collect['error'] as String?,
      models: [for (final m in ((j['models'] as List?) ?? const [])) if (m is Map) LabelModelInfo.fromJson(Map<String, dynamic>.from(m))],
      pairs: PairCounts.fromJson((j['pairs'] as Map?)?.cast<String, dynamic>()),
      cars: CarCounts.fromJson((j['cars'] as Map?)?.cast<String, dynamic>()),
      hasVideo: j['has_video'] as bool?,
    );
  }
}

/// How the "same car?" questions stand.
class PairCounts {
  const PairCounts({this.open = 0, this.same = 0, this.different = 0, this.skipped = 0});

  final int open, same, different, skipped;

  int get total => open + same + different + skipped;

  factory PairCounts.fromJson(Map<String, dynamic>? j) {
    int n(String k) => (j?[k] as num?)?.toInt() ?? 0;
    return PairCounts(open: n('open'), same: n('same'), different: n('different'), skipped: n('skipped'));
  }
}

/// What a person says about two cars.
enum PairAnswer {
  same('same'),
  different('different'),
  notSure('skip');

  const PairAnswer(this.wire);

  /// The word the harvest helper expects.
  final String wire;
}

/// Two cars of one analysis: the same car with a new number, or two cars that look alike?
class PairItem {
  const PairItem({required this.id, required this.kind, required this.reason, required this.task});

  final String id;

  /// `gap`: one car vanished as the other appeared. `twin`: two look-alikes on screen together.
  final String kind;
  final String reason;
  final String? task;

  bool get together => kind == 'twin';

  factory PairItem.fromJson(Map<String, dynamic> j) => PairItem(
        id: '${j['id']}',
        kind: '${j['kind'] ?? 'gap'}',
        reason: '${j['reason'] ?? ''}',
        task: j['task'] as String?,
      );
}

class PairQueue {
  const PairQueue({required this.items});

  final List<PairItem> items;

  factory PairQueue.fromJson(Map<String, dynamic> j) =>
      PairQueue(items: [for (final i in ((j['items'] as List?) ?? const [])) if (i is Map) PairItem.fromJson(Map<String, dynamic>.from(i))]);
}

/// One picture waiting for a person.
class LabelItem {
  const LabelItem({
    required this.id,
    required this.state,
    required this.reason,
    required this.boxes,
    required this.suggested,
    required this.violation,
    required this.width,
    required this.height,
    required this.task,
    required this.ticket,
  });

  final String id;
  final HarvestState state;

  /// The full sentence of why this picture is here (shown on demand, not by default).
  final String reason;
  final List<HarvestBox> boxes;

  /// The boxes are the model's guess.
  final bool suggested;
  final String? violation;
  final int width;
  final int height;
  final String? task;
  final String? ticket;

  double get aspect => (width > 0 && height > 0) ? width / height : 4 / 3;

  factory LabelItem.fromJson(Map<String, dynamic> j) => LabelItem(
        id: '${j['id']}',
        state: HarvestState.fromName(j['state']),
        reason: '${j['reason'] ?? ''}',
        boxes: [for (final b in ((j['boxes'] as List?) ?? const [])) ?HarvestBox.fromJson(b)],
        suggested: j['suggested'] == true,
        violation: j['violation'] as String?,
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
        task: j['task'] as String?,
        ticket: j['ticket'] as String?,
      );
}

class LabelQueue {
  const LabelQueue({required this.model, required this.classes, required this.help, required this.items});

  final String model;
  final List<String> classes;
  final Map<String, String> help;
  final List<LabelItem> items;

  factory LabelQueue.fromJson(Map<String, dynamic> j) => LabelQueue(
        model: '${j['model']}',
        classes: [for (final c in ((j['classes'] as List?) ?? const [])) '$c'],
        help: {for (final e in ((j['help'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        items: [for (final i in ((j['items'] as List?) ?? const [])) if (i is Map) LabelItem.fromJson(Map<String, dynamic>.from(i))],
      );
}

/// Where a car stands: not looked at yet, all its photos are one car, or some photos were marked as another car.
enum CarState {
  open,
  checked,
  split;

  static CarState fromName(Object? name) {
    for (final s in values) {
      if (s.name == '$name') return s;
    }
    return open;
  }
}

class CarCounts {
  const CarCounts({this.open = 0, this.checked = 0, this.split = 0});

  final int open, checked, split;

  int get total => open + checked + split;

  factory CarCounts.fromJson(Map<String, dynamic>? j) {
    int n(String k) => (j?[k] as num?)?.toInt() ?? 0;
    return CarCounts(open: n('open'), checked: n('checked'), split: n('split'));
  }
}

/// One ticketed car in the list: its number, how many photos it has, and whether a person went through them.
class CarSummary {
  const CarSummary({required this.uid, required this.track, required this.photos, required this.first, required this.state});

  final String uid;
  final int track;
  final int photos;

  /// The first photo (the original), a file name inside the evidence folder.
  final String first;
  final CarState state;

  factory CarSummary.fromJson(Map<String, dynamic> j) => CarSummary(
        uid: '${j['uid']}',
        track: (j['track'] as num?)?.toInt() ?? 0,
        photos: (j['photos'] as num?)?.toInt() ?? 0,
        first: '${j['first'] ?? ''}',
        state: CarState.fromName(j['state']),
      );
}

class CarList {
  const CarList({required this.evidenceDir, required this.items, required this.counts});

  /// Where the photos are on this computer.
  final String evidenceDir;
  final List<CarSummary> items;
  final CarCounts counts;

  factory CarList.fromJson(Map<String, dynamic> j) => CarList(
        evidenceDir: '${j['evidence_dir'] ?? ''}',
        items: [for (final i in ((j['items'] as List?) ?? const [])) if (i is Map) CarSummary.fromJson(Map<String, dynamic>.from(i))],
        counts: CarCounts.fromJson((j['counts'] as Map?)?.cast<String, dynamic>()),
      );
}

/// One car and its photos in the order they were taken. The first is the original; [marked] are the ones a person
/// said show a different car.
class CarDetail {
  const CarDetail({required this.uid, required this.track, required this.evidenceDir, required this.photos, required this.marked});

  final String uid;
  final int track;
  final String evidenceDir;
  final List<String> photos;
  final Set<String> marked;

  factory CarDetail.fromJson(Map<String, dynamic> j) => CarDetail(
        uid: '${j['uid']}',
        track: (j['track'] as num?)?.toInt() ?? 0,
        evidenceDir: '${j['evidence_dir'] ?? ''}',
        photos: [for (final p in ((j['photos'] as List?) ?? const [])) '$p'],
        marked: {for (final p in ((j['marked'] as List?) ?? const [])) '$p'},
      );
}
