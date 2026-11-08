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
