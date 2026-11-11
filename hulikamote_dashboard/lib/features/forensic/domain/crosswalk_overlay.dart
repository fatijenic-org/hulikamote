import 'dart:math' as math;
import 'dart:ui';

import 'zone_geometry.dart';

/// The overlay crosswalk of "Pedestrian lane" (the backend's engine/crosswalk_overlay.py is the source of truth; keep the numbers the same).
///
/// For testing the rule on a road that has no crosswalk. The operator places a painted zebra crossing on the picture. It is not part of the
/// video: it belongs to the analysis, is drawn on the photos and the result video, and it IS the crosswalk zone.
/// Stored in the wizard's settings as {x, y, scale, depth, angle, slant, stripes, wear}, the spot in the 1920x1080 reference space.
class CrosswalkOverlay {
  CrosswalkOverlay._();

  static const double sizeShare = 0.22; // band length across the road at scale 1.0, share of the picture width
  static const double depthRatio = 0.38; // band depth / length at depth 1.0, seen from straight above
  static const double minScale = 0.3, maxScale = 3.0;
  static const double minDepth = 0.25, maxDepth = 2.0;
  static const double maxAngle = 90.0; // turned in the picture, degrees clockwise
  static const double maxSlant = 70.0; // perspective: how far the camera looks along the road, degrees
  static const int minStripes = 3, maxStripes = 16;
  static const double fill = 0.58; // share of each stripe slot that is paint

  static const double defaultScale = 1.0, defaultDepth = 1.0, defaultAngle = 0.0, defaultSlant = 30.0, defaultWear = 0.2;
  static const int defaultStripes = 8;

  static double clampScale(double v) => v.isFinite ? v.clamp(minScale, maxScale).toDouble() : defaultScale;
  static double clampDepth(double v) => v.isFinite ? v.clamp(minDepth, maxDepth).toDouble() : defaultDepth;
  static double clampAngle(double v) => v.isFinite ? v.clamp(-maxAngle, maxAngle).toDouble() : defaultAngle;
  static double clampSlant(double v) => v.isFinite ? v.clamp(0.0, maxSlant).toDouble() : defaultSlant;
  static double clampWear(double v) => v.isFinite ? v.clamp(0.0, 1.0).toDouble() : defaultWear;
  static int clampStripes(num v) => v.isFinite ? v.round().clamp(minStripes, maxStripes).toInt() : defaultStripes;

  /// A new crosswalk at [at] (0..1 canvas coordinates), with the normal look.
  static Map<String, dynamic> make(Offset at) => {
    'x': at.dx * ZoneGeometry.refWidth,
    'y': at.dy * ZoneGeometry.refHeight,
    'scale': defaultScale,
    'depth': defaultDepth,
    'angle': defaultAngle,
    'slant': defaultSlant,
    'stripes': defaultStripes,
    'wear': defaultWear,
  };

  static double _num(Map c, String key, double fallback) => (c[key] as num?)?.toDouble() ?? fallback;
  static double scaleOf(Map c) => clampScale(_num(c, 'scale', defaultScale));
  static double depthOf(Map c) => clampDepth(_num(c, 'depth', defaultDepth));
  static double angleOf(Map c) => clampAngle(_num(c, 'angle', defaultAngle));
  static double slantOf(Map c) => clampSlant(_num(c, 'slant', defaultSlant));
  static double wearOf(Map c) => clampWear(_num(c, 'wear', defaultWear));
  static int stripesOf(Map c) => clampStripes(_num(c, 'stripes', defaultStripes.toDouble()));

  /// Where the crosswalk is, as a point in 0..1 canvas coordinates.
  static Offset centerOf(Map c) => Offset(_num(c, 'x', 0) / ZoneGeometry.refWidth, _num(c, 'y', 0) / ZoneGeometry.refHeight);

  /// The four corners (far-left, far-right, near-right, near-left) relative to the centre, in the reference space.
  static List<Offset> corners(Map c) {
    final length = ZoneGeometry.refWidth * sizeShare * scaleOf(c);
    final depth = length * depthRatio * depthOf(c);
    final slant = slantOf(c) * math.pi / 180;
    final far = 1.0 - 0.55 * math.sin(slant); // the far edge's length relative to the near edge
    final flat = 1.0 - 0.45 * math.sin(slant); // how much the depth is squashed
    final roll = angleOf(c) * math.pi / 180;
    return [
      for (final (sx, sy, shrink) in const [(-0.5, -0.5, null), (0.5, -0.5, null), (0.5, 0.5, 1.0), (-0.5, 0.5, 1.0)])
        () {
          final x = sx * length * (shrink ?? far), y = sy * depth * flat;
          return Offset(x * math.cos(roll) - y * math.sin(roll), x * math.sin(roll) + y * math.cos(roll));
        }(),
    ];
  }

  /// The crosswalk's four corners as points in 0..1 canvas coordinates.
  static List<Offset> quad(Map c) {
    final centre = centerOf(c);
    return [
      for (final p in corners(c)) Offset(centre.dx + p.dx / ZoneGeometry.refWidth, centre.dy + p.dy / ZoneGeometry.refHeight),
    ];
  }

  /// The white bars, each a four-corner shape between the far and the near edge of [quad], side by side along the band.
  static List<List<Offset>> bars(List<Offset> quad, int stripes) {
    Offset lerp(Offset a, Offset b, double t) => Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    final n = clampStripes(stripes);
    return [
      for (var k = 0; k < n; k++)
        () {
          final u0 = (k + (1 - fill) / 2) / n, u1 = (k + 1 - (1 - fill) / 2) / n;
          return [lerp(quad[0], quad[1], u0), lerp(quad[0], quad[1], u1), lerp(quad[3], quad[2], u1), lerp(quad[3], quad[2], u0)];
        }(),
    ];
  }

  static bool onBand(Map c, Offset canvasPoint) => ZoneGeometry.inside(quad(c), canvasPoint);

  static Offset _turn(Offset p, double degrees) {
    final a = degrees * math.pi / 180;
    return Offset(p.dx * math.cos(a) - p.dy * math.sin(a), p.dx * math.sin(a) + p.dy * math.cos(a));
  }

  /// The corner that is dragged to resize (the near-right one).
  static Offset resizeHandle(Map c, Size canvas) {
    final q = quad(c);
    return Offset(q[2].dx * canvas.width, q[2].dy * canvas.height);
  }

  /// The knob above the far edge that is dragged to turn the crosswalk.
  static Offset rotateKnob(Map c, Size canvas) {
    final centre = centerOf(c);
    final slant = slantOf(c) * math.pi / 180;
    final halfDepth = ZoneGeometry.refWidth * sizeShare * scaleOf(c) * depthRatio * depthOf(c) * (1.0 - 0.45 * math.sin(slant)) / 2;
    final px = canvas.width / ZoneGeometry.refWidth;
    final up = _turn(Offset(0, -(halfDepth * px + 26)), angleOf(c));
    return Offset(centre.dx * canvas.width, centre.dy * canvas.height) + up;
  }

  /// The scale that puts the resize handle under the pointer.
  static double scaleFor(Map c, Size canvas, Offset pointer) {
    final unit = {...c, 'scale': 1.0};
    final corner = corners(unit)[2];
    final px = canvas.width / ZoneGeometry.refWidth;
    final centre = Offset(centerOf(c).dx * canvas.width, centerOf(c).dy * canvas.height);
    return clampScale((pointer - centre).distance / math.max(corner.distance * px, 1));
  }

  /// The angle that puts the rotate knob under the pointer (the knob sits straight above the crosswalk at angle 0).
  static double angleFor(Map c, Size canvas, Offset pointer) {
    final centre = Offset(centerOf(c).dx * canvas.width, centerOf(c).dy * canvas.height);
    final d = pointer - centre;
    final degrees = math.atan2(d.dy, d.dx) * 180 / math.pi + 90;
    return clampAngle(((degrees + 180) % 360) - 180);
  }
}
