import 'package:flutter/foundation.dart';

import 'violation_catalog.dart';

/// Pipeline options shared by every violation of one analysis.
class PipelineSettings {
  String tracker = 'bytetrack';
  String plateMethod = 'smart';
  String plateFormat = 'ph_standard';
  String ocrEngine = 'easyocr';
  String plateModel = ''; // '' = the active plate model (Models tab)
  String enhancement = 'realesrgan';
  String primaryModel = ''; // '' = the active vehicle detector (Models tab)
  bool useSahi = false;
  int flagSensitivity = 4; // 1 (strict) .. 7 (sensitive)
  int evidenceGap = 5; // one evidence photo every N frames of a flagged car
  bool keepInputVideo = false;
  bool blurPrivacy = true; // TEMPORARY switch: off only for the team's own training videos (saved photos then show faces)

  /// When the video started, typed by the operator ('' = find it in the video). Also the way to test a ban hour.
  String videoStart = '';
}

/// Everything the operator sets up before an analysis starts: the video, the violations,
/// their zones and the pipeline options. Builds the exact `config_json` the backend expects.
class AnalysisDraft extends ChangeNotifier {
  String? videoPath;
  String? videoName;
  String? frameUrl; // first frame, for drawing zones
  double fps = 30;
  int frameCount = 0;

  /// Seconds. 0 until the player or the backend says how long the video is.
  double duration = 0;

  /// The part of the video to analyze: from [trimStart] to [trimEnd] seconds. [trimEnd] null = to the end.
  double trimStart = 0;
  double? trimEnd;

  /// The time (seconds) of the picture zones are drawn on; it must be the trim start, so it is looked up again when
  /// the start moves.
  double? frameSeconds;

  final PipelineSettings settings = PipelineSettings();
  final Set<String> _selected = {};
  final Map<String, Map<String, dynamic>> _configs = {};

  bool get hasVideo => videoPath != null && frameUrl != null;

  /// A video was chosen (its picture for the zones may still be on its way).
  bool get hasVideoPath => videoPath != null;

  /// Where the analysis ends, in seconds (the whole length when no end was set).
  double get effectiveEnd => trimEnd ?? duration;

  /// Seconds of video that will be analyzed (0 while the length is unknown).
  double get keptSeconds => duration > 0 ? (effectiveEnd - trimStart).clamp(0.0, duration) : 0;

  /// Only part of the video is analyzed.
  bool get trimmed => trimStart > 0.001 || (trimEnd != null && duration > 0 && trimEnd! < duration - 0.001);

  /// The chosen video, before anything is known about it (its picture and speed come a moment later).
  void chooseVideo({required String path, required String name}) {
    videoPath = path;
    videoName = name;
    frameUrl = null;
    frameSeconds = null;
    fps = 30;
    frameCount = 0;
    duration = 0;
    trimStart = 0;
    trimEnd = null;
    settings.videoStart = ''; // a time typed for one video is not the next one's
    _selected.clear();
    _configs.clear();
    notifyListeners();
  }

  /// What was learned about the video: its picture (at [seconds]), speed, frame count and length.
  void setFrame({required String url, required double seconds, double? fps, int? frames, double? duration}) {
    frameUrl = url;
    frameSeconds = seconds;
    if (fps != null && fps > 0) this.fps = fps;
    if (frames != null && frames > 0) frameCount = frames;
    if (duration != null && duration > 0) learnDuration(duration);
    notifyListeners();
  }

  /// The length of the video, from the player or the backend (the first to know wins).
  void learnDuration(double seconds) {
    if (seconds <= 0 || duration > 0) return;
    duration = seconds;
    notifyListeners();
  }

  /// Moves the start and/or the end of the part to analyze. Keeps them inside the video and at least a frame apart.
  void setTrim({double? start, double? end}) {
    final length = duration > 0 ? duration : double.infinity;
    final gap = 1 / fps;
    var s = (start ?? trimStart).clamp(0.0, length);
    var e = end ?? effectiveEnd;
    if (e.isInfinite || e <= 0) e = length;
    e = e.clamp(0.0, length);
    if (end == null && e - s < gap) s = (e - gap).clamp(0.0, length);      // the start was dragged to the end
    if (start == null && e - s < gap) e = (s + gap).clamp(0.0, length);    // the end was dragged to the start
    trimStart = s;
    trimEnd = (e.isInfinite || (duration > 0 && e >= duration - 0.001)) ? null : e;   // the full length (or an unknown one) is "no end"
    notifyListeners();
  }

  /// Back to the whole video.
  void resetTrim() {
    trimStart = 0;
    trimEnd = null;
    notifyListeners();
  }

  /// Selected violations in catalog order (stable, independent of click order).
  List<String> get selection => [
    for (final v in ViolationCatalog.selectable)
      if (_selected.contains(v.key)) v.key,
  ];

  bool isSelected(String key) => _selected.contains(key);

  void setVideo({
    required String path,
    required String name,
    required String frame,
    double? fps,
    int? frames,
  }) {
    videoPath = path;
    videoName = name;
    frameUrl = frame;
    this.fps = (fps != null && fps > 0) ? fps : 30;
    frameCount = frames ?? 0;
    frameSeconds = 0;
    trimStart = 0;
    trimEnd = null;
    _selected.clear();
    _configs.clear();
    notifyListeners();
  }

  void toggle(String key, {bool? on}) {
    final next = on ?? !_selected.contains(key);
    next ? _selected.add(key) : _selected.remove(key);
    notifyListeners();
  }

  void selectAll(Iterable<String> keys) {
    _selected
      ..clear()
      ..addAll(keys);
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  /// Vehicle types a type-based rule starts with (same defaults as the backend rule; the operator can change them).
  static const Map<String, List<String>> _defaultVehicleTypes = {
    'illegal_loading': ['bus', 'tricycle', 'truck'],
    'truck_ban': ['truck'],
    'tricycle_on_highway': ['tricycle'],
    'sidewalk_driving': ['car', 'motorcycle', 'bus', 'truck', 'tricycle'],
  };

  /// The mutable per-violation config (same keys and defaults the backend has always received).
  Map<String, dynamic> config(String key) =>
      _configs.putIfAbsent(key, () => defaultConfig(key));

  static Map<String, dynamic> defaultConfig(String key) => {
    'rois': <dynamic>[],
    'time_limit': key == 'pedestrian_lane'
        ? 3.0
        : (key == 'disregarding_signs' || key == 'blocking_intersection'
              ? 5.0
              : (key == 'illegal_loading' || key == 'double_parking' ? 8.0 : 180.0)),
    'allowed_classes': <String>['bus'],
    // Vehicle types a rule applies to: banned in a truck-ban / highway / sidewalk zone, judged for loading.
    'banned_classes': <String>[...?_defaultVehicleTypes[key]],
    // Illegal turn, automatic mode: which turns are NOT allowed at this camera (as the driver sees them).
    'banned_turns': <String>['left'],
    'max_riders': 2,
    // Counterflow: draw the learned flow arrows, and the TEST that treats the opposite direction as legal.
    'show_flow': true,
    'invert_flow': false,
    // Red light: 'camera' reads a box drawn around the light, 'timer' simulates one.
    'light_mode': 'timer',
    'red_start': 0.0,
    'red': 30.0,
    'green': 30.0,
    'yellow': 3.0,
  };

  List<dynamic> zones(String key) => config(key)['rois'] as List;

  bool needsZone(String key) => ViolationCatalog.of(key).needsZone;

  /// Rules that need no drawing: with nothing drawn (and no sign placed) the whole picture is watched, so the whole frame is
  /// captured instead of one area; a zone you do draw still limits the rule to where it is. ("Restricted lane": a camera that
  /// watches only the reserved road needs no drawing; "Tricycle on a national highway" / "Truck ban": ticking the rule says the
  /// whole view is a road where the ban applies; "Counterflow": the direction is learned from the traffic.)
  /// The backend keeps the same list (Violation.whole_frame).
  static const wholeFrameKeys = {
    'counterflow',
    'swerving',
    'illegal_u_turn',
    'illegal_turn',
    'signal_light',
    'truck_ban',
    'tricycle_on_highway',
    'restricted_lane',
    'illegal_loading',
    'double_parking',
    'illegal_parking',
  };

  /// The rules among them that also need the traffic flow when they watch the whole picture: counterflow (which way is legal)
  /// and parking / loading (a stopped vehicle counts only while other traffic drives past). The backend learns the flow by itself
  /// then (Violation.needs_flow); no other rule has anything to do with it.
  static const flowKeys = {'counterflow', 'illegal_loading', 'illegal_parking'};

  /// The rule watches the whole picture: it needs no drawing and nothing is drawn or placed for it.
  bool watchesWholePicture(String key) => wholeFrameKeys.contains(key) && zones(key).isEmpty && signCount(key) == 0;

  /// The traffic flow has to be learned from the video: a selected rule that needs it watches the whole picture.
  bool get learnsFlow => selection.any((k) => flowKeys.contains(k) && watchesWholePicture(k));

  /// "Crossing a solid line" needs no drawing: with no line drawn, the analysis finds the painted solid lines in the video
  /// (the switch in its editor, on unless the operator turned it off). A line that is drawn is used instead.
  bool findsLinesItself(String key) => key == 'crossing_solid_line' && ((config(key)['auto_lines'] as bool?) ?? true);

  /// The overlay signs placed on the picture: for "Restricted lane" [{type, x, y}], for "Illegal loading / unloading" and
  /// "Illegal parking" [{x, y, w, h}], in the 1920x1080 reference space.
  /// Temporary: they belong to this analysis only and are never written into the video.
  List<Map<String, dynamic>> signs(String key) => (config(key).putIfAbsent('signs', () => <dynamic>[]) as List).cast<Map<String, dynamic>>();

  /// Rules where a placed overlay sign is a zone too ("Illegal loading / unloading", "Illegal parking": the sign's box is the banned
  /// area, so a sign is enough and nothing needs drawing). Their signs are [{x, y, w, h}] in the same reference space.
  static const signZoneKeys = {'illegal_loading', 'illegal_parking'};

  /// How many overlay signs are placed for [key] (without creating the list).
  int signCount(String key) => ((config(key)['signs'] as List?) ?? const []).length;

  /// The overlay crosswalks placed on the picture for "Pedestrian lane" (testing): [{x, y, scale, depth, angle, slant, stripes, wear}]
  /// in the 1920x1080 reference space. Each one IS a crosswalk zone; temporary, never written into the video.
  List<Map<String, dynamic>> crosswalks(String key) =>
      (config(key).putIfAbsent('crosswalks', () => <dynamic>[]) as List).cast<Map<String, dynamic>>();

  /// How many overlay crosswalks a rule has (0 for a rule that has none).
  int crosswalkCount(String key) => key == 'pedestrian_lane' ? crosswalks(key).length : 0;

  bool zonesReady(String key) =>
      !needsZone(key) ||
      zones(key).isNotEmpty ||
      (signZoneKeys.contains(key) && signCount(key) > 0) ||
      crosswalkCount(key) > 0 ||
      findsLinesItself(key) ||
      wholeFrameKeys.contains(key);

  /// Selected violations that still need a zone.
  List<String> get missingZones => [
    for (final k in selection)
      if (!zonesReady(k)) k,
  ];

  bool get canStart => hasVideo && selection.isNotEmpty && missingZones.isEmpty;

  /// Evidence photos per second for one flagged car at the chosen gap.
  double get photosPerSecond => fps / settings.evidenceGap;

  /// The upload payload. [activePlateModel] resolves "use the active plate model".
  Map<String, dynamic> buildConfig({String? activePlateModel}) {
    final selected = selection;
    return {
      'active_violations': selected,
      'tracker': settings.tracker,
      'plate_model': settings.plateModel.isNotEmpty
          ? settings.plateModel
          : (activePlateModel ?? 'plate_specialist.onnx'),
      'plate_method': settings.plateMethod,
      'plate_format': settings.plateFormat,
      'ocr_engine': settings.ocrEngine,
      'enhancement': settings.enhancement,
      'primary_model': settings.primaryModel,
      'use_sahi': settings.useSahi,
      'flag_sensitivity': settings.flagSensitivity,
      'evidence_gap': settings.evidenceGap,
      'keep_input_video': settings.keepInputVideo,
      'blur_privacy': settings.blurPrivacy,
      'flow_mode': learnsFlow ? 'auto' : 'zones',
      if (settings.videoStart.trim().isNotEmpty) 'video_start': settings.videoStart.trim(),
      if (videoName != null) 'video_name': videoName,
      if (trimStart > 0.001) 'trim_start': trimStart,
      if (trimEnd != null) 'trim_end': trimEnd,
      'per_violation_configs': {for (final k in selected) k: config(k)},
    };
  }

  void touch() => notifyListeners();

  void reset() {
    settings.videoStart = '';
    videoPath = videoName = frameUrl = null;
    fps = 30;
    frameCount = 0;
    duration = 0;
    trimStart = 0;
    trimEnd = null;
    frameSeconds = null;
    _selected.clear();
    _configs.clear();
    notifyListeners();
  }
}
