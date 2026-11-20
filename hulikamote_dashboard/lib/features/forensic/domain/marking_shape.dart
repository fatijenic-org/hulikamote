import 'dart:ui';

/// A road marking of the live setup as the zone editors see it (the editors live in the Forensic feature and know nothing of the live
/// setup): its shape in the 1920x1080 reference space, to be drawn behind the zones and to put a sign on.
class MarkingShape {
  const MarkingShape({required this.id, required this.kind, required this.label, required this.polygon, this.laneType});

  final String id;
  final String kind; // lane | road | crosswalk | sidewalk
  final String label; // "Lane 1 · Bus lane"
  final List<Offset> polygon;
  final String? laneType; // a lane's type: a key of LaneSigns (the sign that says it)

  /// A good spot for a sign: the middle of the shape (the lane's own middle when that is inside it).
  Offset get anchor {
    if (polygon.isEmpty) return Offset.zero;
    final mean = polygon.fold<Offset>(Offset.zero, (a, b) => a + b) / polygon.length.toDouble();
    if (_inside(mean)) return mean;
    // a bent lane: the middle of its longest edge's pull towards the inside
    var best = polygon.first;
    var bestLen = -1.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i], b = polygon[(i + 1) % polygon.length];
      final len = (b - a).distance;
      final mid = (a + b) / 2;
      final toward = mid + (mean - mid) * 0.05;
      if (len > bestLen && _inside(toward)) {
        bestLen = len;
        best = toward;
      }
    }
    return best;
  }

  bool _inside(Offset p) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) inside = !inside;
    }
    return inside;
  }
}
