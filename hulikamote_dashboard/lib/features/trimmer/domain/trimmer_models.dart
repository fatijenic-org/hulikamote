/// What the backend knows about a video (length, speed, size).
class ProbeInfo {
  const ProbeInfo({required this.duration, required this.fps, required this.width, required this.height});

  final double duration;
  final double fps;
  final int width;
  final int height;

  factory ProbeInfo.fromJson(Map<String, dynamic> json) => ProbeInfo(
        duration: (json['duration'] as num).toDouble(),
        fps: (json['fps'] as num?)?.toDouble() ?? 25,
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );
}

enum JobStatus {
  queued('Waiting'),
  running('Cutting'),
  done('Done'),
  failed('Failed'),
  cancelled('Cancelled');

  const JobStatus(this.label);

  final String label;

  static JobStatus parse(String? text) => values.firstWhere((s) => s.name == text, orElse: () => JobStatus.failed);
}

/// One clip being cut (or waiting to be, or finished) on the laptop.
class TrimJob {
  const TrimJob({
    required this.id,
    required this.source,
    required this.output,
    required this.start,
    required this.end,
    required this.label,
    required this.status,
    this.progress = 0,
    this.error = '',
    this.exact = false,
  });

  final String id;
  final String source;
  final String output;
  final double start;
  final double end;
  final String label;
  final JobStatus status;
  final double progress;
  final String error;
  final bool exact;

  bool get active => status == JobStatus.queued || status == JobStatus.running;

  /// The file's own name, without the folder.
  String get outputName => output.split(RegExp(r'[\\/]')).last;

  factory TrimJob.fromJson(Map<String, dynamic> json) => TrimJob(
        id: json['id'] as String,
        source: json['source'] as String? ?? '',
        output: json['output'] as String? ?? '',
        start: (json['start'] as num?)?.toDouble() ?? 0,
        end: (json['end'] as num?)?.toDouble() ?? 0,
        label: json['label'] as String? ?? '',
        status: JobStatus.parse(json['status'] as String?),
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        error: json['error'] as String? ?? '',
        exact: json['exact'] as bool? ?? false,
      );
}

/// A clip as it is sent to be cut.
class ClipRequest {
  const ClipRequest({required this.start, required this.end, this.label = ''});

  final double start;
  final double end;
  final String label;

  Map<String, dynamic> toJson() => {'start': start, 'end': end, 'label': label};
}
