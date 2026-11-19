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
    this.laneType,
    this.roadClass,
    this.paint = false,
    this.stripes = 8,
    this.wear = 0.2,
    this.realistic = true,
  });

  static const kinds = ['crosswalk', 'road', 'sidewalk']; // what an area can be after "Detect road"
  /// What an area can be in the road markings of the live setup: the same, and the lane (it has a type: who may use it).
  static const markingKinds = ['crosswalk', 'road', 'lane', 'sidewalk'];
  static const lineKinds = ['solid_line', 'stop_line'];

  /// Lane types: the keys of the backend's engine/lane_signs.py SIGNS (keep the two lists the same) and what is said about them.
  /// "Restricted lane" flags every vehicle the type does not allow.
  static const laneTypes = <String, String>{
    'bus_only': 'Bus lane',
    'puv_only': 'PUV lane (bus, jeepney)',
    'motorcycle_only': 'Motorcycle lane',
    'bicycle_only': 'Bike lane',
    'no_trucks': 'No trucks',
    'no_tricycles': 'No tricycles',
    'no_motorcycles': 'No motorcycles',
  };

  /// What kind of road a road area is. "Tricycle on a national highway" takes the national highways.
  static const roadClasses = <String, String>{
    'national_highway': 'National highway',
    'city_road': 'City or provincial road',
    'barangay_road': 'Barangay road',
    'other': 'Other road',
  };
  static const lineStyles = ['solid_white', 'solid_yellow', 'double_yellow'];
  static const minStripes = 3;
  static const maxStripes = 16;
  static const maxPoints = 64; // what the backend accepts for one shape

  static String labelOf(String kind) => switch (kind) {
    'road' => 'Road',
    'lane' => 'Lane',
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
  final List<Offset> arrow; // two points or more: the way the traffic goes, bent where the road bends (only with a flow)
  final String style; // solid_white | solid_yellow | double_yellow, for a solid line
  final bool rule; // a solid line that counts crossings as violations (a found line starts as a hint)
  final String? laneType; // a lane: a key of [laneTypes]; null = any vehicle may use it (the lane only gives a direction)
  final String? roadClass; // a road: a key of [roadClasses]; null = not said
  final bool paint; // a crosswalk shown as a painted zebra on the live video (vehicles drive over it)
  final int stripes; // the zebra's bars (3 to 16)
  final double wear; // how worn the paint is (0 = new, 1 = very worn)
  final bool realistic; // soft edge, grain, dulled to the scene's light; off = flat clean paint

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
      laneType: json['lane_type'] as String?,
      roadClass: json['road_class'] as String?,
      paint: json['paint'] as bool? ?? false,
      stripes: ((json['stripes'] as num?)?.toInt() ?? 8).clamp(minStripes, maxStripes),
      wear: ((json['wear'] as num?)?.toDouble() ?? 0.2).clamp(0.0, 1.0),
      realistic: json['realistic'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    isLine ? 'line' : 'polygon': [for (final p in polygon) [p.dx, p.dy]],
    if (side != null) 'side': side,
    if (hasDirection && flow != null) 'flow': flow,
    if (hasDirection && flow != null && arrow.length >= 2) 'arrow': [for (final p in arrow) [p.dx, p.dy]],
    if (kind == 'solid_line') ...{'style': style, 'rule': rule},
    if (kind == 'lane' && laneType != null) 'lane_type': laneType,
    if (kind == 'road' && roadClass != null) 'road_class': roadClass,
    if (kind == 'crosswalk' && paint) ...{'paint': true, 'stripes': stripes, 'wear': wear, 'realistic': realistic},
  };

  /// A road area or a lane can have a direction.
  bool get hasDirection => kind == 'road' || kind == 'lane';

  /// A changed copy. [clearFlow] removes the direction and its arrow (what a road area that is no longer a road has).
  RoadArea copyWith({
    String? kind,
    List<Offset>? polygon,
    String? flow,
    List<Offset>? arrow,
    String? style,
    bool? rule,
    String? laneType,
    String? roadClass,
    bool? paint,
    int? stripes,
    double? wear,
    bool? realistic,
    bool clearFlow = false,
    bool clearLaneType = false,
    bool clearRoadClass = false,
  }) => RoadArea(
    id: id,
    kind: kind ?? this.kind,
    polygon: polygon ?? this.polygon,
    side: side,
    flow: clearFlow ? null : (flow ?? this.flow),
    arrow: clearFlow ? const [] : (arrow ?? this.arrow),
    style: style ?? this.style,
    rule: rule ?? this.rule,
    laneType: clearLaneType ? null : (laneType ?? this.laneType),
    roadClass: clearRoadClass ? null : (roadClass ?? this.roadClass),
    paint: paint ?? this.paint,
    stripes: stripes ?? this.stripes,
    wear: wear ?? this.wear,
    realistic: realistic ?? this.realistic,
  );

  /// The same shape with every point multiplied by [fx] and [fy] (from the picture's pixels to the 1920x1080 reference space and back).
  RoadArea scaled(double fx, double fy) => RoadArea(
    id: id,
    kind: kind,
    polygon: [for (final p in polygon) Offset(p.dx * fx, p.dy * fy)],
    side: side,
    flow: flow,
    arrow: [for (final p in arrow) Offset(p.dx * fx, p.dy * fy)],
    style: style,
    rule: rule,
    laneType: laneType,
    roadClass: roadClass,
    paint: paint,
    stripes: stripes,
    wear: wear,
    realistic: realistic,
  );

  /// The same shape under another name.
  RoadArea withId(String newId) => RoadArea(
    id: newId,
    kind: kind,
    polygon: polygon,
    side: side,
    flow: flow,
    arrow: arrow,
    style: style,
    rule: rule,
    laneType: laneType,
    roadClass: roadClass,
    paint: paint,
    stripes: stripes,
    wear: wear,
    realistic: realistic,
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
