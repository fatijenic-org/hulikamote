import 'dart:ui';

/// Zones are stored in a fixed 1920x1080 reference space (what the backend scales from),
/// whatever size the drawing canvas happens to be. The canvas works in 0..1 coordinates
/// so a drawing survives a window resize.
class ZoneGeometry {
  ZoneGeometry._();

  static const double refWidth = 1920;
  static const double refHeight = 1080;

  /// 0..1 canvas coordinates -> [[x, y], ...] in the 1920x1080 reference space.
  static List<List<double>> toReference(List<Offset> normalized) => [
    for (final p in normalized) [p.dx * refWidth, p.dy * refHeight],
  ];

  /// Reference-space points (as the backend stores them) -> 0..1 canvas coordinates.
  static List<Offset> fromReference(List<dynamic> points) => [
    for (final p in points)
      Offset(
        ((p as List)[0] as num).toDouble() / refWidth,
        (p[1] as num).toDouble() / refHeight,
      ),
  ];

  /// The legal-flow / prohibited-direction vector of an arrow, in reference pixels.
  static Map<String, double> vectorOf(Offset from, Offset to) => {
    'x_dir': (to.dx - from.dx) * refWidth,
    'y_dir': (to.dy - from.dy) * refHeight,
  };

  /// The piece of a drawn line (points in 0..1) that is within [radius] pixels of [at] (canvas pixels): which piece
  /// (`segment` 0 is the one between point 0 and point 1) and the spot on it nearest to [at], in 0..1 again.
  /// Null when no piece is that close. Grabbing the middle of a line to bend it uses this.
  static ({int segment, Offset point})? nearSegment(
    List<Offset> normalized,
    Offset at,
    Size canvas, {
    double radius = 12,
  }) {
    ({int segment, Offset point})? best;
    var bestDistance = radius;
    for (var i = 0; i + 1 < normalized.length; i++) {
      final a = Offset(normalized[i].dx * canvas.width, normalized[i].dy * canvas.height);
      final b = Offset(normalized[i + 1].dx * canvas.width, normalized[i + 1].dy * canvas.height);
      final ab = b - a;
      final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
      if (lengthSquared == 0) continue;
      final along = (((at - a).dx * ab.dx + (at - a).dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
      final nearest = a + ab * along;
      final distance = (at - nearest).distance;
      if (distance <= bestDistance) {
        bestDistance = distance;
        best = (segment: i, point: Offset(nearest.dx / canvas.width, nearest.dy / canvas.height));
      }
    }
    return best;
  }

  /// Whether [p] is inside the polygon (points in 0..1; the edge itself counts as either).
  static bool inside(List<Offset> polygon, Offset p) {
    if (polygon.length < 3) return false;
    var odd = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) odd = !odd;
    }
    return odd;
  }

  /// Index of the point within [radius] pixels of [at] (canvas pixels), or null.
  static int? hit(
    List<Offset> normalized,
    Offset at,
    Size canvas, {
    double radius = 14,
  }) {
    for (var i = normalized.length - 1; i >= 0; i--) {
      final p = Offset(
        normalized[i].dx * canvas.width,
        normalized[i].dy * canvas.height,
      );
      if ((p - at).distance <= radius) return i;
    }
    return null;
  }
}
