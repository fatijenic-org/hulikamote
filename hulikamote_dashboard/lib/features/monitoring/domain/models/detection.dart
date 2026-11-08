/// A box that shows WHY a vehicle was flagged (the bare head, the phone, each rider...), in frame pixels [x, y, w, h].
class DetectionMark {
  final List<int> bbox;
  final String label;

  const DetectionMark({required this.bbox, required this.label});

  factory DetectionMark.fromJson(Map<String, dynamic> json) => DetectionMark(
    bbox: (json['bbox'] as List).map((e) => (e as num).toInt()).toList(),
    label: json['label'] as String? ?? '',
  );
}

class Detection {
  final String cls;
  final bool isViolator;
  final double confidence;
  final List<int> bbox;
  final String? userName;
  final int? trackId;
  final List<DetectionMark> marks;

  const Detection({
    required this.cls,
    required this.isViolator,
    required this.confidence,
    required this.bbox,
    this.userName,
    this.trackId,
    this.marks = const [],
  });

  factory Detection.fromJson(Map<String, dynamic> json) => Detection(
    cls: json['class'] as String,
    isViolator: json['is_violator'] as bool? ?? false,
    confidence: (json['confidence'] as num).toDouble(),
    bbox: (json['bbox'] as List).map((e) => (e as num).toInt()).toList(),
    userName: json['user_name'] as String?,
    trackId: (json['track_id'] as num?)?.toInt(),
    marks: [
      for (final m in (json['marks'] as List? ?? const []))
        if (m is Map) DetectionMark.fromJson(Map<String, dynamic>.from(m)),
    ],
  );
}

/// A zone the Live Monitor learned from the picture by itself (crosswalk, stop line, solid line), in frame pixels.
class RoadZone {
  final String violation; // pedestrian_lane | red_light | crossing_solid_line
  final List<List<double>> polygon; // [[x, y], ...]
  final List<List<double>> line; // the stop line / solid line, two points, or empty
  final bool bestEffort; // the finder is weaker for lines: labelled
  final bool hint; // only shown, never used as a rule

  const RoadZone({
    required this.violation,
    required this.polygon,
    this.line = const [],
    this.bestEffort = false,
    this.hint = false,
  });

  factory RoadZone.fromJson(Map<String, dynamic> json) {
    List<List<double>> points(Object? raw) => [
      for (final p in (raw as List? ?? const []))
        if (p is List && p.length >= 2) [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
    ];
    return RoadZone(
      violation: json['violation'] as String? ?? '',
      polygon: points(json['polygon']),
      line: points(json['line']),
      bestEffort: json['best_effort'] as bool? ?? false,
      hint: json['hint'] as bool? ?? false,
    );
  }

  /// "Crosswalk (learned)"; lines say "hint only" (not a rule) or "best effort" (a rule, the finder is weaker there).
  String get label {
    final name = switch (violation) {
      'pedestrian_lane' => 'Crosswalk',
      'red_light' => 'Stop line',
      'crossing_solid_line' => 'Solid line',
      _ => violation,
    };
    return hint ? '$name (hint only)' : (bestEffort ? '$name (learned, best effort)' : '$name (learned)');
  }
}

class VideoFrame {
  final String type;
  final String transport; // 'hls' or 'websocket'
  final String? hlsUrl;   // set when transport == 'hls'
  final int? frameWidth;
  final int? frameHeight;
  final bool mock;
  final String? frameBase64;
  final List<Detection> detections;
  final String timestamp;
  final Map<String, dynamic>? road; // what the road learner is doing (state, message, progress...)
  final List<RoadZone> roadZones; // the learned zones in use, for the overlay

  const VideoFrame({
    required this.type,
    this.transport = 'websocket',
    this.hlsUrl,
    this.frameWidth,
    this.frameHeight,
    required this.mock,
    this.frameBase64,
    required this.detections,
    required this.timestamp,
    this.road,
    this.roadZones = const [],
  });

  factory VideoFrame.fromJson(Map<String, dynamic> json) => VideoFrame(
    type: json['type'] as String,
    transport: json['transport'] as String? ?? 'websocket',
    hlsUrl: json['hls_url'] as String?,
    frameWidth: json['frame_width'] as int?,
    frameHeight: json['frame_height'] as int?,
    mock: json['mock'] as bool? ?? true,
    frameBase64: json['frame_base64'] as String?,
    detections: (json['detections'] as List)
        .map((e) => Detection.fromJson(e as Map<String, dynamic>))
        .toList(),
    timestamp: json['timestamp'] as String,
    road: json['road'] is Map ? Map<String, dynamic>.from(json['road'] as Map) : null,
    roadZones: [
      for (final z in (json['road_zones'] as List? ?? const []))
        if (z is Map) RoadZone.fromJson(Map<String, dynamic>.from(z)),
    ],
  );
}
