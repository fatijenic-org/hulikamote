import 'dart:math' as math;
import 'dart:ui';

import 'zone_geometry.dart';

/// The look of a line painted on the picture (the backend's engine/line_paint.py is the source of truth; keep the two the same).
///
/// A saved solid line that carries a `look` map is painted like road paint on the evidence photos and the result video, along the points the
/// rule judges. The paint is only a picture of the line: the rule uses the points. The line is turned by turning its points.
class LinePaint {
  LinePaint._();

  static const List<(String, String)> styles = [
    ('solid_yellow', 'Yellow'),
    ('solid_white', 'White'),
    ('double_yellow', 'Double yellow'),
    ('dashed_white', 'White dashed'),
  ];
  static const double minWidth = 0.4, maxWidth = 3.0;

  /// A new look: yellow solid, normal width, a little worn, thinner farther up the picture.
  static Map<String, dynamic> newLook() => {'style': 'solid_yellow', 'width': 1.0, 'wear': 0.2, 'taper': 0.6};

  static String styleOf(Map look) => styles.any((s) => s.$1 == look['style']) ? look['style'] as String : 'solid_yellow';

  static double _num(Map look, String key, double fallback, double low, double high) {
    final v = look[key];
    final n = v is num ? v.toDouble() : fallback;
    return n.isFinite ? n.clamp(low, high).toDouble() : fallback;
  }

  static double widthOf(Map look) => _num(look, 'width', 1.0, minWidth, maxWidth);
  static double wearOf(Map look) => _num(look, 'wear', 0.2, 0, 1);
  static double taperOf(Map look) => _num(look, 'taper', 0.6, 0, 1);

  /// The points (0..1) turned by [degrees] (clockwise on the picture) round their middle, kept inside the picture. The turn is made in
  /// picture pixels, so a line that is turned 10 degrees looks turned 10 degrees.
  static List<Offset> rotated(List<Offset> points, double degrees) {
    if (points.isEmpty) return points;
    final px = [for (final p in points) Offset(p.dx * ZoneGeometry.refWidth, p.dy * ZoneGeometry.refHeight)];
    final centre = Offset(px.map((p) => p.dx).reduce((a, b) => a + b) / px.length, px.map((p) => p.dy).reduce((a, b) => a + b) / px.length);
    final a = degrees * math.pi / 180;
    final c = math.cos(a), s = math.sin(a);
    return [
      for (final p in px)
        Offset(
          ((centre.dx + (p.dx - centre.dx) * c - (p.dy - centre.dy) * s) / ZoneGeometry.refWidth).clamp(0.0, 1.0),
          ((centre.dy + (p.dx - centre.dx) * s + (p.dy - centre.dy) * c) / ZoneGeometry.refHeight).clamp(0.0, 1.0),
        ),
    ];
  }
}
