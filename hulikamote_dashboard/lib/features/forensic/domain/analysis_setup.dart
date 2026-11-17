import 'forensic_models.dart' show formatVideoTime;

/// One line of the setup: "Tracker" / "DeepSORT".
class SetupRow {
  const SetupRow(this.label, this.value);
  final String label;
  final String value;
}

/// A titled group of rows.
class SetupSection {
  const SetupSection(this.title, this.rows);
  final String title;
  final List<SetupRow> rows;
}

/// What one violation was told to do in this analysis (only the settings that rule really uses).
class ViolationSetup {
  const ViolationSetup(this.key, this.rows);
  final String key;
  final List<SetupRow> rows;
}

/// The settings an analysis ran with, read from its forensic_config.json: the file, the violations,
/// the models and the review options. Built once; the screen only draws it.
class AnalysisSetup {
  const AnalysisSetup({
    required this.taskId,
    required this.videoName,
    required this.violations,
    required this.sections,
    required this.perViolation,
  });

  final String taskId;

  /// The video's full file name, null when the analysis did not save it (older analyses).
  final String? videoName;
  final List<String> violations;
  final List<SetupSection> sections;
  final List<ViolationSetup> perViolation;

  // Which setting belongs to which rule. The config holds every key for every rule, so only these are shown.
  static const _timeLimit = {
    'illegal_parking',
    'pedestrian_lane',
    'blocking_intersection',
    'illegal_loading',
    'double_parking',
    'disregarding_signs',
  };
  static const _bannedClasses = {
    'illegal_loading',
    'truck_ban',
    'tricycle_on_highway',
    'sidewalk_driving',
    'disregarding_signs',
  };

  factory AnalysisSetup.fromJson(Map<String, dynamic> j, {required String taskId}) {
    final name = '${j['video_name'] ?? ''}'.trim();
    final violations = [for (final v in (j['active_violations'] as List?) ?? const []) '$v'];
    final w = (j['video_native_width'] as num?)?.toInt();
    final h = (j['video_native_height'] as num?)?.toInt();
    final start = (j['trim_start'] as num?)?.toDouble();
    final end = (j['trim_end'] as num?)?.toDouble();
    final clock = '${j['video_start'] ?? ''}'.trim();
    final model = '${j['primary_model'] ?? ''}'.trim();

    final file = <SetupRow>[
      if (w != null && h != null && w > 0 && h > 0) SetupRow('Video size', '$w × $h'),
      if (start != null && start > 0) SetupRow('Started at', formatVideoTime(start)),
      if (end != null && end > 0) SetupRow('Analyzed up to', formatVideoTime(end)),
      if (clock.isNotEmpty) SetupRow('Video start time', clock),
    ];
    final detection = <SetupRow>[
      SetupRow('Tracker', _pretty('${j['tracker'] ?? ''}')),
      SetupRow('Vehicle model', model.isEmpty ? 'Active model' : model),
      SetupRow('Plate model', '${j['plate_model'] ?? '—'}'),
      SetupRow('Plate reading', _pretty('${j['plate_method'] ?? ''}')),
      SetupRow('Plate format', _pretty('${j['plate_format'] ?? ''}')),
      SetupRow('Text reader', _pretty('${j['ocr_engine'] ?? ''}')),
      SetupRow('Plate sharpening', _pretty('${j['enhancement'] ?? ''}')),
      SetupRow('Small-object search', _onOff(j['use_sahi'])),
    ];
    final review = <SetupRow>[
      SetupRow('Flag sensitivity', '${j['flag_sensitivity'] ?? '—'}'),
      SetupRow('Evidence photo gap', '${j['evidence_gap'] ?? '—'}'),
      SetupRow('Kept the video', _yesNo(j['keep_input_video'])),
      SetupRow('Blurred plates for privacy', _yesNo(j['blur_privacy'])),
    ];

    final configs = j['per_violation_configs'] is Map ? Map<String, dynamic>.from(j['per_violation_configs'] as Map) : const <String, dynamic>{};
    return AnalysisSetup(
      taskId: taskId,
      videoName: name.isEmpty ? null : name,
      violations: violations,
      sections: [
        if (file.isNotEmpty) SetupSection('Video', file),
        SetupSection('Detection', detection),
        SetupSection('Review', review),
      ],
      perViolation: [
        for (final v in violations)
          ViolationSetup(v, _violationRows(v, configs[v] is Map ? Map<String, dynamic>.from(configs[v] as Map) : const {})),
      ],
    );
  }

  static List<SetupRow> _violationRows(String key, Map<String, dynamic> c) {
    int count(String field) => c[field] is List ? (c[field] as List).length : 0;
    String list(String field) => [for (final e in (c[field] as List?) ?? const []) '$e'].join(', ');
    final zones = count('rois');
    final signs = count('signs');
    final walks = count('crosswalks');
    final rows = <SetupRow>[
      SetupRow('Area', zones > 0 ? '$zones drawn' : 'None drawn'),
      if (signs > 0) SetupRow('Signs placed', '$signs'),
      if (walks > 0) SetupRow('Crosswalks placed', '$walks'),
    ];
    final limit = c['time_limit'];
    if (_timeLimit.contains(key) && limit is num) rows.add(SetupRow('Time limit', '${_num(limit)} s'));
    if (key == 'restricted_lane' && count('allowed_classes') > 0) rows.add(SetupRow('Allowed vehicles', list('allowed_classes')));
    if (_bannedClasses.contains(key) && count('banned_classes') > 0) rows.add(SetupRow('Banned vehicles', list('banned_classes')));
    if (key == 'illegal_turn' && count('banned_turns') > 0) rows.add(SetupRow('Banned turns', list('banned_turns')));
    if (key == 'overloading' && c['max_riders'] is num) rows.add(SetupRow('Most riders allowed', _num(c['max_riders'] as num)));
    if (key == 'counterflow' && c['invert_flow'] == true) rows.add(const SetupRow('Flow', 'Reversed'));
    if (key == 'red_light') {
      final mode = '${c['light_mode'] ?? ''}';
      rows.add(SetupRow(
        'Light',
        mode == 'timer'
            ? 'Timer: red ${_num(c['red'] as num? ?? 0)} s, green ${_num(c['green'] as num? ?? 0)} s, yellow ${_num(c['yellow'] as num? ?? 0)} s'
            : _pretty(mode),
      ));
    }
    if (key == 'truck_ban' && c['ban_windows'] is List && (c['ban_windows'] as List).isNotEmpty) {
      rows.add(SetupRow('Ban hours', [
        for (final w in c['ban_windows'] as List)
          if (w is List && w.length >= 2) '${w[0]}–${w[1]}',
      ].join(', ')));
    }
    return rows;
  }

  static String _num(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
  static String _yesNo(Object? v) => v == true ? 'Yes' : 'No';
  static String _onOff(Object? v) => v == true ? 'On' : 'Off';

  static const _names = {
    'deepsort': 'DeepSORT',
    'bytetrack': 'ByteTrack',
    'easyocr': 'EasyOCR',
    'realesrgan': 'Real-ESRGAN',
  };

  /// "ph_standard" -> "PH standard", "deepsort" -> "DeepSORT", empty -> "—".
  static String _pretty(String s) {
    final t = s.trim();
    if (t.isEmpty) return '—';
    final known = _names[t.toLowerCase()];
    if (known != null) return known;
    final words = t.split('_').map((w) => (w == 'ph' || w == 'uk') ? w.toUpperCase() : w).toList();
    final text = words.join(' ');
    return text[0].toUpperCase() + text.substring(1);
  }
}
