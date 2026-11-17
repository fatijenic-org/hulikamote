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

/// One shape of the road picture the operator can correct, in the frozen picture's pixels: an AREA (crosswalk, road, sidewalk: a closed
/// shape of 3 or more points) or a LINE (solid line, stop line: an open line of 2 or more points). A curve is simply more points.
/// A road area may have a direction ([flow]: 'in' = traffic comes toward the camera, 'out' = goes away) and an [arrow] that shows it.
class RoadArea {
  const RoadArea({
    required this.id,
    required this.kind,
    required this.polygon,
    this.side,
    this.flow,
    this.arrow = const [],
    this.style = 'solid_white',
    this.rule = false,
  });

  static const kinds = ['crosswalk', 'road', 'sidewalk']; // what an area can be
  static const lineKinds = ['solid_line', 'stop_line'];
  static const lineStyles = ['solid_white', 'solid_yellow', 'double_yellow'];
  static const maxPoints = 64; // what the backend accepts for one shape

  static String labelOf(String kind) => switch (kind) {
    'road' => 'Road',
    'sidewalk' => 'Sidewalk',
    'solid_line' => 'Solid line',
    'stop_line' => 'Stop line',
    _ => 'Crosswalk',
  };

  static String styleLabel(String style) => switch (style) {
    'solid_yellow' => 'Yellow',
    'double_yellow' => 'Double yellow',
    _ => 'White',
  };

  final String id;
  final String kind; // crosswalk | road | sidewalk | solid_line | stop_line
  final List<Offset> polygon; // the points: closed for an area, an open line for a line (the name is kept from the first version)
  final String? side; // left | right, for a sidewalk
  final String? flow; // in | out, for a road area that has a direction
  final List<Offset> arrow; // two points: the way the traffic goes (only with a flow)
  final String style; // solid_white | solid_yellow | double_yellow, for a solid line
  final bool rule; // a solid line that counts crossings as violations (a found line starts as a hint)

  bool get isLine => lineKinds.contains(kind);

  /// The least points the shape needs: 2 for a line, 3 for an area.
  int get minPoints => isLine ? 2 : 3;

  factory RoadArea.fromJson(Map<String, dynamic> json) {
    List<Offset> points(Object? raw) => [
      for (final p in (raw as List? ?? const []))
        if (p is List && p.length >= 2) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    final kind = json['kind'] as String? ?? 'road';
    final isLine = lineKinds.contains(kind);
    return RoadArea(
      id: json['id'] as String? ?? '',
      kind: kind,
      polygon: points(isLine ? json['line'] : json['polygon']),
      side: json['side'] as String?,
      flow: json['flow'] as String?,
      arrow: points(json['arrow']),
      style: json['style'] as String? ?? 'solid_white',
      rule: json['rule'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    isLine ? 'line' : 'polygon': [for (final p in polygon) [p.dx, p.dy]],
    if (side != null) 'side': side,
    if (kind == 'road' && flow != null) 'flow': flow,
    if (kind == 'road' && flow != null && arrow.length == 2) 'arrow': [for (final p in arrow) [p.dx, p.dy]],
    if (kind == 'solid_line') ...{'style': style, 'rule': rule},
  };

  /// A changed copy. [clearFlow] removes the direction and its arrow (what a road area that is no longer a road has).
  RoadArea copyWith({
    String? kind,
    List<Offset>? polygon,
    String? flow,
    List<Offset>? arrow,
    String? style,
    bool? rule,
    bool clearFlow = false,
  }) => RoadArea(
    id: id,
    kind: kind ?? this.kind,
    polygon: polygon ?? this.polygon,
    side: side,
    flow: clearFlow ? null : (flow ?? this.flow),
    arrow: clearFlow ? const [] : (arrow ?? this.arrow),
    style: style ?? this.style,
    rule: rule ?? this.rule,
  );

  /// The middle of the shape's points, left to right (to say "incoming on the left").
  double get centreX => polygon.isEmpty ? 0 : polygon.map((p) => p.dx).reduce((a, b) => a + b) / polygon.length;
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
    this.flowState = 'none',
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
  final List<RoadArea> zones; // the draft the operator can correct (crosswalks, road sides, sidewalks, lines)
  final bool edited; // the operator corrected it
  final String flowState; // two_way | one_way_in | one_way_out | none: what the traffic showed about its direction

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
    flowState: (json['flow'] is Map ? (json['flow'] as Map)['state'] as String? : null) ?? 'none',
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

/// "Incoming on the left, outgoing on the right" for the road areas that have a direction, left to right; '' when none has.
String roadDirectionsText(List<RoadArea> areas) {
  final sides = [for (final a in areas) if (a.kind == 'road' && (a.flow == 'in' || a.flow == 'out')) a]
    ..sort((a, b) => a.centreX.compareTo(b.centreX));
  if (sides.isEmpty) return '';
  String name(RoadArea a) => a.flow == 'in' ? 'incoming' : 'outgoing';
  if (sides.length == 1) return 'Only ${name(sides.first)} traffic was seen. If the road is two-way, the other side was empty: add it by hand.';
  const places = ['on the left', 'in the middle', 'on the right'];
  final parts = <String>[
    for (final (i, s) in sides.indexed)
      '${name(s)} ${sides.length == 2 ? (i == 0 ? 'on the left' : 'on the right') : (i < places.length ? places[i] : '#${i + 1}')}',
  ];
  return 'Traffic: ${parts.join(', ')}.';
}
