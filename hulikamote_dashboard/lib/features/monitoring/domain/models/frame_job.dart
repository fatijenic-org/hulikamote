/// One picture the grab has collected (the picture itself is fetched by its [id]).
class FrameChoice {
  const FrameChoice({required this.id, required this.label, this.width = 0, this.height = 0});

  final int id;

  /// A file: the time in the video ("1:23"). A camera: seconds since the first picture ("3 s").
  final String label;
  final int width;
  final int height;

  factory FrameChoice.fromJson(Map<String, dynamic> json) => FrameChoice(
        id: (json['id'] as num).toInt(),
        label: '${json['label'] ?? ''}',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );
}

/// The pictures collected so far for the setup's "pick a frame" step (the answer of GET /settings/video/frames).
class FrameJob {
  const FrameJob({
    required this.job,
    required this.state,
    this.kind = '',
    this.error = '',
    this.expected = 0,
    this.frames = const [],
  });

  /// A new grab has a new number: it keeps the picture cache from showing a picture of the last one.
  final int job;

  /// idle | grabbing | done | failed
  final String state;

  /// file | camera ('' until the backend has understood the source)
  final String kind;
  final String error;

  /// How many pictures the grab is after.
  final int expected;
  final List<FrameChoice> frames;

  bool get working => state == 'grabbing';
  bool get failed => state == 'failed';
  bool get fromCamera => kind == 'camera';

  factory FrameJob.fromJson(Map<String, dynamic> json) => FrameJob(
        job: (json['job'] as num?)?.toInt() ?? 0,
        state: '${json['state'] ?? 'idle'}',
        kind: '${json['kind'] ?? ''}',
        error: '${json['error'] ?? ''}',
        expected: (json['expected'] as num?)?.toInt() ?? 0,
        frames: [
          for (final f in (json['frames'] as List? ?? const [])) FrameChoice.fromJson(Map<String, dynamic>.from(f as Map)),
        ],
      );
}
