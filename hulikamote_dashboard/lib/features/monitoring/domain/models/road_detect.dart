import 'dart:ui' show Offset;

/// One step of the road walkthrough, as the backend reports it (engine/road_lines.py WALKTHROUGH).
class RoadStep {
  const RoadStep({
    required this.id,
    required this.title,
    required this.about,
    required this.state,
    required this.hasOverlay,
  });

  final String id; // steady | empty | motion | direction | road | topview | paint | marks
  final String title;
  final String about; // one plain sentence on what the step does
  final String state; // waiting | running | done | skipped
  final bool hasOverlay; // a picture to lay over the frame exists (the first step has none)

  factory RoadStep.fromJson(Map<String, dynamic> json) => RoadStep(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    about: json['about'] as String? ?? '',
    state: json['state'] as String? ?? 'waiting',
    hasOverlay: json['has_overlay'] as bool? ?? false,
  );
}

/// One area of the road picture the operator can correct: a crosswalk, the road or a sidewalk, in the frozen picture's pixels.
class RoadArea {
  const RoadArea({required this.id, required this.kind, required this.polygon, this.side});

  static const kinds = ['crosswalk', 'road', 'sidewalk'];

  static String labelOf(String kind) => switch (kind) {
    'road' => 'Road',
    'sidewalk' => 'Sidewalk',
    _ => 'Crosswalk',
  };

  final String id;
  final String kind; // crosswalk | road | sidewalk
  final List<Offset> polygon;
  final String? side; // left | right, for a sidewalk

  factory RoadArea.fromJson(Map<String, dynamic> json) => RoadArea(
    id: json['id'] as String? ?? '',
    kind: json['kind'] as String? ?? 'road',
    polygon: [
      for (final p in (json['polygon'] as List? ?? const []))
        if (p is List && p.length >= 2) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ],
    side: json['side'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'polygon': [for (final p in polygon) [p.dx, p.dy]],
    if (side != null) 'side': side,
  };

  RoadArea copyWith({String? kind, List<Offset>? polygon}) =>
      RoadArea(id: id, kind: kind ?? this.kind, polygon: polygon ?? this.polygon, side: side);
}

/// What "Detect road" is doing: GET /settings/video/road/detect.
class RoadDetectStatus {
  const RoadDetectStatus({
    required this.state,
    this.progressS = 0,
    this.needS = 40,
    this.size = const [],
    this.steps = const [],
    this.reason,
    this.found = const {},
    this.rules = const [],
    this.hints = const [],
    this.applied = false,
    this.zones = const [],
    this.edited = false,
  });

  final String state; // none | collecting | analysing | done | failed
  final double progressS; // seconds of footage collected so far (while collecting)
  final double needS;
  final List<int> size; // the frozen picture, [width, height]
  final List<RoadStep> steps;
  final String? reason; // why it failed
  final Map<String, int> found; // crosswalks / stop_lines / solid_lines
  final List<String> rules; // violations that would get a learned zone
  final List<String> hints; // marks that are only shown
  final bool applied;
  final List<RoadArea> zones; // the draft the operator can correct (crosswalks to be used, the road, the sidewalks)
  final bool edited; // the operator corrected it

  factory RoadDetectStatus.fromJson(Map<String, dynamic> json) => RoadDetectStatus(
    state: json['state'] as String? ?? 'none',
    progressS: (json['progress_s'] as num?)?.toDouble() ?? 0,
    needS: (json['need_s'] as num?)?.toDouble() ?? 40,
    size: [for (final v in (json['size'] as List? ?? const [])) (v as num).toInt()],
    steps: [
      for (final s in (json['steps'] as List? ?? const []))
        if (s is Map) RoadStep.fromJson(Map<String, dynamic>.from(s)),
    ],
    reason: json['reason'] as String?,
    found: {
      for (final e in ((json['found'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt(),
    },
    rules: [for (final v in (json['rules'] as List? ?? const [])) v as String],
    hints: [for (final v in (json['hints'] as List? ?? const [])) v as String],
    applied: json['applied'] as bool? ?? false,
    zones: [
      for (final z in (json['zones'] as List? ?? const []))
        if (z is Map) RoadArea.fromJson(Map<String, dynamic>.from(z)),
    ],
    edited: json['edited'] as bool? ?? false,
  );

  /// Width / height of the frozen picture (the overlays share it).
  double get aspect => size.length == 2 && size[1] > 0 ? size[0] / size[1] : 16 / 9;

  bool get finished => state == 'done' || state == 'failed';

  /// "2 crosswalks, 1 stop line" - what was found, in words.
  String get foundText {
    final parts = <String>[];
    for (final (key, one, many) in const [
      ('crosswalks', 'crosswalk', 'crosswalks'),
      ('stop_lines', 'stop line', 'stop lines'),
      ('solid_lines', 'solid line', 'solid lines'),
    ]) {
      final n = found[key] ?? 0;
      if (n > 0) parts.add('$n ${n == 1 ? one : many}');
    }
    return parts.join(', ');
  }
}
