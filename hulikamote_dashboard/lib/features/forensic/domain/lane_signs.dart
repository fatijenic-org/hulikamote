import 'dart:math' as math;
import 'dart:ui';

/// The overlay signs of "Restricted lane" (the backend's engine/lane_signs.py is the source of truth; keep the two lists the same).
///
/// A sign is placed by the operator on a spot of a road in the picture. It is not part of the video: it is an overlay that belongs to
/// the analysis, drawn on the evidence photos and the result video, and it says who may use the road it stands on.
class LaneSign {
  const LaneSign(this.key, this.line1, this.line2, this.allowed);

  final String key;
  final String line1; // the two lines written on the sign
  final String line2;
  final List<String> allowed; // vehicle types that MAY use the road; the others are flagged

  String get label => '$line1 $line2';
}

class LaneSigns {
  LaneSigns._();

  static const List<String> vehicleTypes = ['bus', 'jeepney', 'motorcycle', 'car', 'truck', 'tricycle', 'bicycle'];

  static List<String> _allBut(String banned) => [
    for (final t in vehicleTypes)
      if (t != banned) t,
  ];

  static final List<LaneSign> all = [
    const LaneSign('bus_only', 'BUS', 'LANE', ['bus']),
    const LaneSign('puv_only', 'PUV', 'ONLY', ['bus', 'jeepney']),
    const LaneSign('motorcycle_only', 'MOTORCYCLE', 'LANE', ['motorcycle']),
    const LaneSign('bicycle_only', 'BIKE', 'LANE', ['bicycle']),
    LaneSign('no_trucks', 'NO', 'TRUCKS', _allBut('truck')),
    LaneSign('no_tricycles', 'NO', 'TRICYCLES', _allBut('tricycle')),
    LaneSign('no_motorcycles', 'NO', 'MOTORCYCLES', _allBut('motorcycle')),
  ];

  static LaneSign? of(String key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// "bus, jeepney": what a sign allows, in words.
  static String allowedText(String key) => (of(key)?.allowed ?? const <String>[]).join(', ');
}

/// How a sign sits on the picture: its size, and the handles that resize and turn it. Same numbers as the backend draws with
/// (engine/lane_signs.py: 8.5% of the picture width at scale 1.0), so the editor shows what the photos and the video will show.
class SignGeometry {
  SignGeometry._();

  static const double widthShare = 0.085;
  static const double heightRatio = 0.62;
  static const double minScale = 0.3;
  static const double maxScale = 3.0;
  static const double maxAngle = 90.0; // turned in the picture, degrees clockwise
  static const double maxTilt = 70.0; // turned away from the camera round its upright axis, degrees

  static double clampScale(double v) => v.isFinite ? v.clamp(minScale, maxScale).toDouble() : 1.0;
  static double clampAngle(double v) => v.isFinite ? v.clamp(-maxAngle, maxAngle).toDouble() : 0.0;
  static double clampTilt(double v) => v.isFinite ? v.clamp(-maxTilt, maxTilt).toDouble() : 0.0;

  /// Width of a sign in pixels of a canvas [canvas] wide.
  static double width(Size canvas, double scale) => canvas.width * widthShare * scale;

  static double height(Size canvas, double scale) => width(canvas, scale) * heightRatio;

  static Offset _turn(Offset p, double degrees) {
    final a = degrees * math.pi / 180;
    return Offset(p.dx * math.cos(a) - p.dy * math.sin(a), p.dx * math.sin(a) + p.dy * math.cos(a));
  }

  /// The corner that is dragged to resize (bottom right of the sign, turned with it).
  static Offset resizeHandle(Offset center, double w, double h, double angle) => center + _turn(Offset(w / 2, h / 2), angle);

  /// The knob above the sign that is dragged to turn it.
  static Offset rotateKnob(Offset center, double w, double h, double angle) => center + _turn(Offset(0, -h / 2 - 26), angle);

  /// Whether [p] is on the sign itself (the board, a little generously), for a sign centred on [center].
  static bool onBoard(Offset center, double w, double h, double angle, Offset p) {
    final local = _turn(p - center, -angle);
    return local.dx.abs() <= w / 2 + 6 && local.dy.abs() <= h / 2 + 6;
  }

  /// The scale that puts the resize handle under the pointer.
  static double scaleFor(Size canvas, Offset center, Offset pointer) {
    final w = canvas.width * widthShare;
    final halfDiagonal = 0.5 * math.sqrt(w * w + (w * heightRatio) * (w * heightRatio));
    return clampScale((pointer - center).distance / halfDiagonal);
  }

  /// The angle that puts the rotate knob under the pointer (the knob sits straight above the sign at angle 0).
  static double angleFor(Offset center, Offset pointer) {
    final d = pointer - center;
    final degrees = math.atan2(d.dy, d.dx) * 180 / math.pi + 90;
    return clampAngle(((degrees + 180) % 360) - 180);
  }
}
