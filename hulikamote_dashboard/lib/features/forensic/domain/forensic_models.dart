/// Typed view of what the forensic backend returns (report.json tickets, history, status).
/// The raw maps stay available (`raw`) because the backend's ticket endpoints want them back.
library;

/// What the reviewer decided about a ticket's violation.
enum ReviewStatus {
  pending,
  confirmed,
  rejected;

  /// The status string the violations table stores.
  String get backendValue => switch (this) {
    ReviewStatus.pending => 'pending',
    ReviewStatus.confirmed => 'approved',
    ReviewStatus.rejected => 'rejected',
  };

  static ReviewStatus fromBackend(String? s) => switch (s) {
    'approved' => ReviewStatus.confirmed,
    'rejected' => ReviewStatus.rejected,
    _ => ReviewStatus.pending,
  };
}

const Set<String> _unreadPlate = {
  '',
  'unidentified',
  'no_plate_found',
  'none',
  'null',
};

/// "0:04.2" / "1:23.5" from seconds into the video; "—" when unknown.
String formatVideoTime(double? seconds) {
  if (seconds == null || seconds.isNaN || seconds < 0) return '—';
  final m = seconds ~/ 60;
  final s = seconds - m * 60;
  return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
}

/// One photo of the flagged vehicle, with what the pipeline knew at that moment.
/// A close-up kept as extra evidence: the picture a specialist model looked at (the helmet crop, the cabin crop ...) with
/// the model's boxes drawn on it. Taken at about the time of the [EvidenceFrame] it belongs to.
class FrameDetail {
  final String file; // the close-up picture, in the evidence folder like the photos
  final String kind; // helmet | seatbelt | phone | mirror
  final String label; // what the model concluded: NO HELMET, 1/2 MIRRORS ...
  final String? violation;
  final double? confidence;

  const FrameDetail({required this.file, required this.kind, required this.label, this.violation, this.confidence});

  factory FrameDetail.fromJson(Map<String, dynamic> j) => FrameDetail(
    file: '${j['file']}',
    kind: '${j['kind'] ?? ''}',
    label: '${j['label'] ?? ''}',
    violation: j['violation'] as String?,
    confidence: (j['confidence'] as num?)?.toDouble(),
  );

  /// Plain-language name of the check this picture comes from.
  String get title => switch (kind) {
    'helmet' => 'Helmet check',
    'seatbelt' => 'Seatbelt check',
    'phone' => 'Phone check',
    'mirror' => 'Side-mirror check',
    _ => 'Close-up',
  };
}

class EvidenceFrame {
  final String file;
  final double? t;
  final List<int>? bbox; // [x, y, w, h] of the vehicle in the full frame
  final String? plate; // plate text read at this moment
  final String? crop; // plate crop file linked to this frame
  final String? clean; // the vehicle without drawn boxes (wider than the box), when the run saved it
  final String? vehicleClass;
  final List<FrameDetail> details; // close-ups of what the models looked at, taken around this moment

  const EvidenceFrame({
    required this.file,
    this.t,
    this.bbox,
    this.plate,
    this.crop,
    this.clean,
    this.vehicleClass,
    this.details = const [],
  });

  factory EvidenceFrame.fromJson(Map<String, dynamic> j) => EvidenceFrame(
    file: '${j['file']}',
    t: (j['t'] as num?)?.toDouble(),
    bbox: (j['bbox'] as List?)?.map((e) => (e as num).toInt()).toList(),
    plate: _cleanPlate(j['plate']),
    crop: j['crop'] as String?,
    clean: j['clean'] as String?,
    vehicleClass: j['vclass'] as String?,
    details: [
      for (final d in (j['details'] as List?) ?? const [])
        if (d is Map && d['file'] != null) FrameDetail.fromJson(Map<String, dynamic>.from(d)),
    ],
  );

  /// Pixels the vehicle covers: a proxy for "how clearly it is shown".
  int get vehicleArea =>
      (bbox != null && bbox!.length == 4) ? bbox![2] * bbox![3] : 0;

  String get timeLabel => formatVideoTime(t);
}

/// One plate crop the OCR looked at (raw, optionally enhanced) and what it read.
class PlateCrop {
  final String file;
  final String? enhanced;
  final String? context;
  final String raw;
  final String cleaned;
  final double? confidence;
  final double? t;

  /// Votes this crop's cleaned read collected across all crops.
  final double points;

  const PlateCrop({
    required this.file,
    this.enhanced,
    this.context,
    this.raw = '',
    this.cleaned = '',
    this.confidence,
    this.t,
    this.points = 0,
  });

  bool get hasRead => !_unreadPlate.contains(cleaned.toLowerCase());
}

/// A review hint from the backend: possible duplicate car, identity jump...
class TicketFlag {
  final String type; // possible_duplicate | identity_jump | ...
  final String? otherUid;
  final String detail;

  const TicketFlag({required this.type, this.otherUid, this.detail = ''});

  factory TicketFlag.fromJson(Map<String, dynamic> j) => TicketFlag(
    type: '${j['type']}',
    otherUid: j['other_uid'] as String?,
    detail: '${j['detail'] ?? ''}',
  );

  bool get isDuplicate => type == 'possible_duplicate';

  String get title => switch (type) {
    'possible_duplicate' => 'Possibly the same car as another ticket',
    'identity_jump' => 'The tracker may have switched cars',
    _ => 'Needs a look',
  };
}

/// One flagged vehicle: what it did, the evidence, and what was read from its plate.
class ForensicTicket {
  /// Stable id: the backend's `ticket_uid`, or `t<track>` for reports made before uids existed.
  final String uid;
  final bool hasUid;
  final int trackId;
  final List<String> violations;
  final String plateText;
  final String? plateRaw;
  final bool plateLengthWarning;

  /// The reviewer typed this plate (the system read it differently, or not at all).
  final bool plateManual;

  /// What the system read before the reviewer's edit; null when it read nothing.
  final String? plateOcr;
  final List<EvidenceFrame> frames;
  final List<PlateCrop> crops;
  final List<TicketFlag> flags;
  final List<String> dbIds;
  final Map<String, dynamic> metadata;
  final Map<String, double> voteTally;
  final String? winningCropFile;

  /// The map exactly as the backend sent it.
  final Map<String, dynamic> raw;

  const ForensicTicket({
    required this.uid,
    required this.hasUid,
    required this.trackId,
    required this.violations,
    required this.plateText,
    required this.plateRaw,
    required this.plateLengthWarning,
    this.plateManual = false,
    this.plateOcr,
    required this.frames,
    required this.crops,
    required this.flags,
    required this.dbIds,
    required this.metadata,
    required this.voteTally,
    required this.winningCropFile,
    required this.raw,
  });

  factory ForensicTicket.fromJson(Map<String, dynamic> j) {
    final track = trackNumberOf(j['track_id']);
    final uid = j['ticket_uid'] as String?;

    // Frames: evidence_paths is the authoritative order; evidence_meta adds time / plate / box.
    final metaByFile = <String, Map<String, dynamic>>{};
    for (final m in ((j['evidence_meta'] as List?) ?? const [])) {
      if (m is Map) metaByFile['${m['file']}'] = Map<String, dynamic>.from(m);
    }
    final paths = ((j['evidence_paths'] as List?) ?? const [])
        .map((e) => '$e')
        .toList();
    final files = paths.isNotEmpty ? paths : metaByFile.keys.toList();
    final frames = [
      for (final f in files)
        EvidenceFrame.fromJson(metaByFile[f] ?? {'file': f}),
    ];

    // Plate crops: plate_crop_paths (winner first) joined with crop_results (what was read).
    final tally = <String, double>{
      for (final e in ((j['vote_tally'] as Map?) ?? const {}).entries)
        '${e.key}': (e.value as num).toDouble(),
    };
    final resultByRaw = <String, Map<String, dynamic>>{};
    for (final r in ((j['crop_results'] as List?) ?? const [])) {
      if (r is Map) {
        resultByRaw['${r['image_raw']}'] = Map<String, dynamic>.from(r);
      }
    }
    final cropFiles = ((j['plate_crop_paths'] as List?) ?? const [])
        .map((e) => '$e')
        .toList();
    final orderedCrops = cropFiles.isNotEmpty
        ? cropFiles
        : resultByRaw.keys.toList();
    final crops = [
      for (final c in orderedCrops)
        () {
          final r = resultByRaw[c];
          final cleaned = '${r?['cleaned'] ?? ''}';
          return PlateCrop(
            file: c,
            enhanced: r?['image_sr'] as String?,
            context: r?['image_context'] as String?,
            raw: '${r?['raw'] ?? ''}',
            cleaned: cleaned,
            confidence: (r?['confidence'] as num?)?.toDouble(),
            t: (r?['t'] as num?)?.toDouble(),
            points: tally[cleaned] ?? 0,
          );
        }(),
    ];

    return ForensicTicket(
      uid: uid ?? 't$track',
      hasUid: uid != null,
      trackId: track,
      violations: ((j['violations'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      plateText: '${j['plate_text'] ?? 'unidentified'}',
      plateRaw: _cleanPlate(j['plate_raw']),
      plateLengthWarning: j['plate_length_warning'] == true,
      plateManual: j['plate_manual'] == true,
      plateOcr: _cleanPlate(j['plate_ocr']),
      frames: frames,
      crops: crops,
      flags: [
        for (final f in ((j['flags'] as List?) ?? const []))
          if (f is Map) TicketFlag.fromJson(Map<String, dynamic>.from(f)),
      ],
      dbIds: ((j['db_ids'] as List?) ?? const []).map((e) => '$e').toList(),
      metadata: Map<String, dynamic>.from((j['metadata'] as Map?) ?? const {}),
      voteTally: tally,
      winningCropFile: j['winning_crop'] as String?,
      raw: Map<String, dynamic>.from(j),
    );
  }

  /// Parses a backend ticket list, skipping entries that are not objects.
  static List<ForensicTicket> parseList(Iterable<dynamic> list) => [
    for (final t in list)
      if (t is Map) ForensicTicket.fromJson(Map<String, dynamic>.from(t)),
  ];

  bool get plateRead => !_unreadPlate.contains(plateText.toLowerCase());
  bool get isFlagged => flags.isNotEmpty;
  int get frameCount => frames.length;

  /// Short id for display: first 6 characters of the uid.
  String get shortId => uid.length > 6 ? uid.substring(0, 6) : uid;

  /// Index of the clearest frame: the one where the vehicle covers the most pixels.
  int get heroIndex {
    if (frames.isEmpty) return 0;
    var best = 0;
    var area = -1;
    for (var i = 0; i < frames.length; i++) {
      if (frames[i].vehicleArea > area) {
        area = frames[i].vehicleArea;
        best = i;
      }
    }
    return area > 0 ? best : frames.length ~/ 2;
  }

  EvidenceFrame? get hero => frames.isEmpty ? null : frames[heroIndex];

  /// Seconds into the video where the evidence starts / ends.
  ({double start, double end})? get span {
    final ts = [
      for (final f in frames)
        if (f.t != null) f.t!,
    ];
    if (ts.isEmpty) return null;
    ts.sort();
    return (start: ts.first, end: ts.last);
  }

  /// The most common vehicle class across the frames (car, truck, motorcycle...).
  String? get vehicleClass {
    final counts = <String, int>{};
    for (final f in frames) {
      final c = f.vehicleClass;
      if (c != null && c.isNotEmpty) counts[c] = (counts[c] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Plate reads ranked by votes, best first.
  List<MapEntry<String, double>> get candidates {
    final list = voteTally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// The crop the reviewer's plate feedback refers to by default.
  PlateCrop? get bestCrop {
    if (crops.isEmpty) return null;
    final w = winningCropFile;
    if (w != null) {
      for (final c in crops) {
        if (c.file == w) return c;
      }
    }
    return crops.first;
  }
}

/// One finished analysis in the Library.
class RunSummary {
  final String taskId;
  final DateTime createdAt;
  final int ticketCount;
  final String? videoUrl;
  final String reportUrl;

  /// The operator pressed "Stop here": only part of the video (or of the plates) was analyzed.
  final bool stoppedEarly;

  /// The analysis is still going: tickets already released can be reviewed, more arrive as cars leave the scene.
  final bool running;

  const RunSummary({
    required this.taskId,
    required this.createdAt,
    required this.ticketCount,
    required this.videoUrl,
    required this.reportUrl,
    this.stoppedEarly = false,
    this.running = false,
  });

  factory RunSummary.fromJson(Map<String, dynamic> j) => RunSummary(
    taskId: '${j['task_id']}',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (((j['created_at'] as num?) ?? 0) * 1000).toInt(),
    ),
    ticketCount: (j['ticket_count'] as num?)?.toInt() ?? 0,
    videoUrl: j['video_url'] as String?,
    reportUrl: '${j['report_url']}',
    stoppedEarly: j['stopped_early'] == true,
    running: j['running'] == true,
  );

  String get shortId => taskId.length > 8 ? taskId.substring(0, 8) : taskId;
}

/// Progress of a running analysis, as the status endpoint reports it.
class RunStatus {
  final String status; // processing | completed | failed | cancelled
  final double progress; // 0..100
  final String? resultVideo;
  final List<ForensicTicket> tickets;
  final String? error;

  /// What the backend is doing right now, in words ("Reading plates: 12 of 340"); empty when it has nothing to add.
  final String message;

  /// Set when "Stop here" cut the analysis short (when, or how many plates were read).
  final Map<String, dynamic>? stoppedEarly;

  /// Tickets released so far. The status of a running analysis leaves the list itself out (ask for it with
  /// `tickets: true`), but always says how many there are.
  final int ticketCount;

  const RunStatus({
    required this.status,
    required this.progress,
    this.resultVideo,
    this.tickets = const [],
    this.error,
    this.message = '',
    this.stoppedEarly,
    this.ticketCount = 0,
  });

  factory RunStatus.fromJson(Map<String, dynamic> j) {
    final tickets = ForensicTicket.parseList((j['tickets'] as List?) ?? const []);
    return RunStatus(
      status: '${j['status']}',
      progress: ((j['progress'] as num?) ?? 0).toDouble(),
      resultVideo: j['result_video'] as String?,
      tickets: tickets,
      error: j['error'] as String?,
      message: '${j['message'] ?? ''}',
      stoppedEarly: j['stopped_early'] is Map ? Map<String, dynamic>.from(j['stopped_early'] as Map) : null,
      ticketCount: (j['ticket_count'] as num?)?.toInt() ?? tickets.length,
    );
  }

  bool get isDone => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
}

/// The tracker number of a ticket. The backend writes plain numbers, but a merged ticket is "3 & 7" and a split one
/// "5 (split)": the first number stands for the ticket (-1 when there is none).
int trackNumberOf(Object? v) {
  if (v is num) return v.toInt();
  final m = RegExp(r'\d+').firstMatch('$v');
  return m == null ? -1 : int.parse(m.group(0)!);
}

/// A plate text worth showing: null for the backend's "unidentified" placeholders.
String? _cleanPlate(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return _unreadPlate.contains(s.toLowerCase()) ? null : s;
}
