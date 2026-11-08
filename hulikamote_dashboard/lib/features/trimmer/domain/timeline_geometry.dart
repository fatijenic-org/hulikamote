import 'trim_session.dart';

enum HitKind { start, end, body, empty }

class TimelineHit {
  const TimelineHit(this.kind, [this.clip]);

  final HitKind kind;
  final TrimClip? clip;
}

/// Maps seconds to pixels on the timeline and back, and says what is under the pointer.
class TimelineGeometry {
  const TimelineGeometry({required this.width, required this.duration});

  final double width;
  final double duration;

  /// How close (px) the pointer must be to a clip's edge to grab it.
  static const handleSlop = 10.0;

  double xOf(double seconds) => duration <= 0 ? 0 : seconds / duration * width;

  double tOf(double x) => duration <= 0 || width <= 0 ? 0 : (x / width * duration).clamp(0.0, duration);

  /// What the pointer at [x] would grab: a handle first (the selected clips' handles win), then a clip's body, else nothing.
  TimelineHit hit(double x, List<TrimClip> clips, Set<int> selected) {
    TimelineHit? best;
    var bestDistance = double.infinity;
    for (final c in clips) {
      final bonus = selected.contains(c.id) ? 0.5 : 0.0;       // a selected clip's edge beats a neighbour's at the same distance
      for (final edge in [(HitKind.start, c.start), (HitKind.end, c.end)]) {
        final d = (x - xOf(edge.$2)).abs() - bonus;
        if (d <= handleSlop && d < bestDistance) {
          best = TimelineHit(edge.$1, c);
          bestDistance = d;
        }
      }
    }
    if (best != null) return best;
    final t = tOf(x);
    for (final c in [...clips.reversed.where((c) => selected.contains(c.id)), ...clips.reversed]) {
      if (t >= c.start && t <= c.end) return TimelineHit(HitKind.body, c);
    }
    return const TimelineHit(HitKind.empty);
  }

  /// Seconds between ruler labels so they are at least [minPixels] apart.
  double rulerStep({double minPixels = 90}) {
    const steps = <double>[0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200];
    if (duration <= 0 || width <= 0) return 1;
    final pixelsPerSecond = width / duration;
    return steps.firstWhere((s) => s * pixelsPerSecond >= minPixels, orElse: () => steps.last);
  }
}
