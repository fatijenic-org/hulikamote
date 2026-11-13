import 'dart:math' as math;
import 'dart:ui';

import 'line_paint.dart';
import 'parking_reasons.dart';
import 'zone_geometry.dart';

/// The overlay box signs of "Illegal loading / unloading" (NO LOADING / UNLOADING) and "Illegal parking" (NO PARKING). The backend's
/// engine/loading_signs.py is the source of truth for what a sign means; keep the two the same.
///
/// A sign is a box placed anywhere on the picture and resized by the operator. The box IS the no-loading area. It is not part of the
/// video: it belongs to the analysis, is drawn on the evidence photos and the result video, and goes when a new analysis starts.
///
/// Stored as {x, y, w, h} (centre and size) in the 1920x1080 reference space, like a drawn zone. The canvas works in 0..1.
class LoadingSigns {
  LoadingSigns._();

  static const String ruleKey = 'illegal_loading';
  static const List<String> lines = ['NO LOADING', 'UNLOADING'];

  static const String parkingRuleKey = 'illegal_parking';
  static const List<String> parkingLines = ['NO', 'PARKING'];

  /// The two lines of text on a sign of [rule]; for Illegal parking they depend on what the sign marks ([kind], see parking_reasons.dart).
  static List<String> linesFor(String rule, {String? kind}) => rule == parkingRuleKey ? ParkingReasons.of(kind).lines : lines;

  /// What a sign of [rule] bans, for the words on the screen.
  static String banFor(String rule) => switch (rule) {
    parkingRuleKey => 'no-parking',
    'double_parking' => 'no-double-parking',
    'blocking_intersection' => 'keep-clear',
    'truck_ban' => 'no-trucks',
    'tricycle_on_highway' => 'no-tricycles',
    'sidewalk_driving' => 'no-vehicles',
    _ => 'no-loading',
  };

  /// The object placed for each rule that has one fixed object (Illegal parking picks its own, see parking_reasons.dart).
  static const Map<String, String> ruleKinds = {
    'double_parking': 'double_parking',
    'blocking_intersection': 'keep_clear',
    'truck_ban': 'no_trucks',
    'tricycle_on_highway': 'no_tricycles',
    'sidewalk_driving': 'sidewalk',
  };

  static const double defaultWidth = 420; // reference pixels: about a car-and-a-half long stretch of kerb in a 1080p picture
  static const double defaultHeight = 230;
  static const double minSide = 48;

  // ── what stands in the box (a realistic object drawn by the backend, engine/overlay_objects.py) ──

  static const double minScale = 0.3, maxScale = 3.0, maxAngle = 90.0, maxTilt = 70.0;
  static const List<String> stands = ['none', 'post', 'tripod'];

  /// The object that stands in the box of [sign]: for Illegal parking what it marks (sign, hydrant ...), for Illegal loading the plate.
  static String objectKind(String rule, Map<String, dynamic> sign) => rule == parkingRuleKey ? ParkingReasons.of(sign['kind'] as String?).key : (ruleKinds[rule] ?? 'no_loading');

  /// A plate can stand on a pole or a tripod; a hydrant and a painted kerb stand alone.
  static bool standable(String kind) => kind != 'hydrant' && kind != 'corner';

  static double _look(Map<String, dynamic> s, String key, double fallback, double low, double high) {
    final v = s[key];
    final n = v is num ? v.toDouble() : fallback;
    return n.isFinite ? n.clamp(low, high).toDouble() : fallback;
  }

  static double scaleOf(Map<String, dynamic> s) => _look(s, 'scale', 1.0, minScale, maxScale);
  static double angleOf(Map<String, dynamic> s) => _look(s, 'angle', 0.0, -maxAngle, maxAngle);
  static double tiltOf(Map<String, dynamic> s) => _look(s, 'tilt', 0.0, -maxTilt, maxTilt);

  /// 'none', 'post' or 'tripod' (the default for a plate is a pole).
  static String standOf(Map<String, dynamic> s, String kind) => !standable(kind) ? 'none' : (stands.contains(s['stand']) ? s['stand'] as String : 'post');

  static void resetLook(Map<String, dynamic> s) {
    for (final k in ['scale', 'angle', 'tilt', 'stand']) {
      s.remove(k);
    }
  }

  /// The tint of the banned area, the same as the backend's (engine/overlay_objects.py KINDS).
  static Color tintOf(String kind) => switch (kind) {
    'sign' => const Color(0xFF145AC8),
    'driveway' || 'keep_clear' => const Color(0xFFFFBE00),
    'sidewalk' => const Color(0xFF145AC8),
    'no_loading' => const Color(0xFFFF8C00),
    _ => const Color(0xFFC82828), // hydrant, fire station, corner
  };

  // ── a free-shaped area: the banned area can be any polygon and the object can stand anywhere ("Edit shape") ──

  static const int minAreaPoints = 3;

  static bool hasArea(Map<String, dynamic> s) => s['area'] is List && (s['area'] as List).length >= minAreaPoints;

  /// The corners of the banned area in 0..1: the free shape when there is one, else the box.
  static List<Offset> areaOf(Map<String, dynamic> s) {
    if (hasArea(s)) {
      return [
        for (final p in s['area'] as List) Offset((p[0] as num).toDouble() / ZoneGeometry.refWidth, (p[1] as num).toDouble() / ZoneGeometry.refHeight),
      ];
    }
    final r = rectOf(s);
    return [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  }

  /// Sets the free shape; the box (x, y, w, h) follows it, because it is what the rest of the wizard and the backend fall back on.
  static void setArea(Map<String, dynamic> s, List<Offset> points) {
    final pts = [for (final p in points) Offset(p.dx.clamp(0.0, 1.0).toDouble(), p.dy.clamp(0.0, 1.0).toDouble())];
    s['area'] = [for (final p in pts) [p.dx * ZoneGeometry.refWidth, p.dy * ZoneGeometry.refHeight]];
    var l = pts.first.dx, t = pts.first.dy, r = l, b = t;
    for (final p in pts) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    _setRect(s, Rect.fromLTRB(l, t, math.max(r, l + minSide / ZoneGeometry.refWidth), math.max(b, t + minSide / ZoneGeometry.refHeight)));
  }

  /// Turns the box into a free shape (its four corners).
  static void startArea(Map<String, dynamic> s) {
    if (!hasArea(s)) setArea(s, areaOf(s));
  }

  /// Back to a box: the box that holds the shape, with the object in its middle.
  static void clearArea(Map<String, dynamic> s) {
    s.remove('area');
    s.remove('ax');
    s.remove('ay');
  }

  /// Where the object stands, 0..1: where it was put, else the middle of the box.
  static Offset anchorOf(Map<String, dynamic> s) {
    final x = s['ax'], y = s['ay'];
    return x is num && y is num ? Offset(x.toDouble() / ZoneGeometry.refWidth, y.toDouble() / ZoneGeometry.refHeight) : rectOf(s).center;
  }

  static void setAnchor(Map<String, dynamic> s, Offset n) {
    s['ax'] = n.dx.clamp(0.0, 1.0) * ZoneGeometry.refWidth;
    s['ay'] = n.dy.clamp(0.0, 1.0) * ZoneGeometry.refHeight;
  }

  /// Turns the shape by [degrees] (clockwise on the picture) round its middle.
  static void rotateArea(Map<String, dynamic> s, double degrees) => setArea(s, LinePaint.rotated(areaOf(s), degrees));

  static void moveVertex(Map<String, dynamic> s, int v, Offset to) {
    final pts = areaOf(s);
    if (v < 0 || v >= pts.length) return;
    pts[v] = to;
    setArea(s, pts);
  }

  /// The corner of a free shape within [radius] canvas pixels of [at], or null.
  static int? vertexAt(Map<String, dynamic> s, Offset at, Size canvas, {double radius = 16}) {
    if (!hasArea(s)) return null;
    final pts = areaOf(s);
    int? best;
    var bestDistance = radius;
    for (var i = 0; i < pts.length; i++) {
      final d = (Offset(pts[i].dx * canvas.width, pts[i].dy * canvas.height) - at).distance;
      if (d <= bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// Adds a corner in the middle of edge [edge] (the one from corner [edge] to the next) and gives back its number.
  static int insertVertex(Map<String, dynamic> s, int edge) {
    final pts = areaOf(s);
    pts.insert(edge + 1, Offset.lerp(pts[edge], pts[(edge + 1) % pts.length], 0.5)!);
    setArea(s, pts);
    return edge + 1;
  }

  /// Takes a corner away; a shape keeps at least three. False when it was not possible.
  static bool removeVertex(Map<String, dynamic> s, int v) {
    if (!hasArea(s) || (s['area'] as List).length <= minAreaPoints) return false;
    final pts = areaOf(s)..removeAt(v);
    setArea(s, pts);
    return true;
  }

  static bool _inside(Offset p, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) inside = !inside;
    }
    return inside;
  }

  /// The corners, in the order of [cornerAt]: top left, top right, bottom right, bottom left.
  static const int corners = 4;

  /// A new sign centred on [at] (0..1), kept inside the picture.
  static Map<String, dynamic> make(Offset at, {String? kind}) {
    final sign = <String, dynamic>{'x': at.dx * ZoneGeometry.refWidth, 'y': at.dy * ZoneGeometry.refHeight, 'w': defaultWidth, 'h': defaultHeight};
    if (kind != null) sign['kind'] = kind; // Illegal parking: what the sign marks (a hydrant, a corner ...)
    fit(sign);
    return sign;
  }

  static double _n(Map<String, dynamic> s, String k) => (s[k] as num).toDouble();

  /// The sign's box in 0..1 canvas coordinates.
  static Rect rectOf(Map<String, dynamic> s) => Rect.fromCenter(
    center: Offset(_n(s, 'x') / ZoneGeometry.refWidth, _n(s, 'y') / ZoneGeometry.refHeight),
    width: _n(s, 'w') / ZoneGeometry.refWidth,
    height: _n(s, 'h') / ZoneGeometry.refHeight,
  );

  static void _setRect(Map<String, dynamic> s, Rect r) {
    s['x'] = r.center.dx * ZoneGeometry.refWidth;
    s['y'] = r.center.dy * ZoneGeometry.refHeight;
    s['w'] = r.width * ZoneGeometry.refWidth;
    s['h'] = r.height * ZoneGeometry.refHeight;
  }

  /// Keeps the sign inside the picture and not smaller than [minSide].
  static void fit(Map<String, dynamic> s) {
    final w = _n(s, 'w').clamp(minSide, ZoneGeometry.refWidth).toDouble();
    final h = _n(s, 'h').clamp(minSide, ZoneGeometry.refHeight).toDouble();
    s['w'] = w;
    s['h'] = h;
    s['x'] = _n(s, 'x').clamp(w / 2, ZoneGeometry.refWidth - w / 2).toDouble();
    s['y'] = _n(s, 'y').clamp(h / 2, ZoneGeometry.refHeight - h / 2).toDouble();
  }

  /// The corner of the sign within [radius] canvas pixels of [at], or null.
  static int? cornerAt(Map<String, dynamic> s, Offset at, Size canvas, {double radius = 16}) {
    if (hasArea(s)) return null; // a free shape has its own corners, see vertexAt
    final r = rectOf(s);
    final points = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    int? best;
    var bestDistance = radius;
    for (var i = 0; i < points.length; i++) {
      final d = (Offset(points[i].dx * canvas.width, points[i].dy * canvas.height) - at).distance;
      if (d <= bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// The sign whose box contains [at] (canvas pixels): the one placed last wins where boxes overlap. Null when none does.
  static int? bodyAt(List<Map<String, dynamic>> signs, Offset at, Size canvas) {
    final n = Offset(at.dx / canvas.width, at.dy / canvas.height);
    for (var i = signs.length - 1; i >= 0; i--) {
      if (hasArea(signs[i]) ? _inside(n, areaOf(signs[i])) : rectOf(signs[i]).contains(n)) return i;
    }
    return null;
  }

  /// What a press at [at] grabs. A free shape that is [selected] first: its object (the diamond), a corner, the middle of an edge (a new
  /// corner is wanted there, see [insertVertex]). Then a box corner (to resize; the opposite corner stays) or the body (to move). Null: nothing.
  static ({int i, bool resize, Offset grab, Offset anchor, int? vertex, int? edge, bool object})? grab(
    List<Map<String, dynamic>> signs,
    Offset at,
    Size canvas, {
    int? selected,
  }) {
    Offset px(Offset n) => Offset(n.dx * canvas.width, n.dy * canvas.height);
    final sel = selected;
    if (sel != null && sel >= 0 && sel < signs.length && hasArea(signs[sel])) {
      final s = signs[sel];
      if ((px(anchorOf(s)) - at).distance <= 16) {
        return (i: sel, resize: false, grab: Offset.zero, anchor: Offset.zero, vertex: null, edge: null, object: true);
      }
      final v = vertexAt(s, at, canvas);
      if (v != null) return (i: sel, resize: false, grab: Offset.zero, anchor: Offset.zero, vertex: v, edge: null, object: false);
      final pts = areaOf(s);
      for (var k = 0; k < pts.length; k++) {
        if ((px(Offset.lerp(pts[k], pts[(k + 1) % pts.length], 0.5)!) - at).distance <= 12) {
          return (i: sel, resize: false, grab: Offset.zero, anchor: Offset.zero, vertex: null, edge: k, object: false);
        }
      }
    }
    for (var i = signs.length - 1; i >= 0; i--) {
      final corner = cornerAt(signs[i], at, canvas);
      if (corner == null) continue;
      final r = rectOf(signs[i]);
      final opposite = [r.bottomRight, r.bottomLeft, r.topLeft, r.topRight][corner];
      return (i: i, resize: true, grab: Offset.zero, anchor: opposite, vertex: null, edge: null, object: false);
    }
    final i = bodyAt(signs, at, canvas);
    if (i == null) return null;
    final centre = rectOf(signs[i]).center;
    return (i: i, resize: false, grab: Offset(at.dx / canvas.width, at.dy / canvas.height) - centre, anchor: Offset.zero, vertex: null, edge: null, object: false);
  }

  /// Moves a grabbed sign so that it follows the pointer [to] (0..1), without leaving the picture. A free shape moves whole, with its object.
  static void moveBy(Map<String, dynamic> s, Offset to, Offset grab) {
    if (hasArea(s)) {
      final r = rectOf(s);
      final want = to - grab; // where the middle of the shape's box should be
      final d = Offset(
        (want.dx - r.center.dx).clamp(-r.left, 1 - r.right).toDouble(),
        (want.dy - r.center.dy).clamp(-r.top, 1 - r.bottom).toDouble(),
      );
      final anchor = anchorOf(s) + d;
      final custom = s['ax'] is num && s['ay'] is num;
      setArea(s, [for (final p in areaOf(s)) p + d]);
      if (custom) setAnchor(s, anchor);
      return;
    }
    s['x'] = (to.dx - grab.dx) * ZoneGeometry.refWidth;
    s['y'] = (to.dy - grab.dy) * ZoneGeometry.refHeight;
    fit(s);
  }

  /// Resizes a sign: one corner follows the pointer [to] (0..1), the corner opposite to it ([anchor]) stays. The sign never gets
  /// smaller than [minSide]; dragging across the anchor flips the box instead of breaking it.
  static void resizeTo(Map<String, dynamic> s, Offset to, Offset anchor) {
    // One axis: the dragged side keeps at least [minimum] away from the fixed side, on the side the pointer is; at the edge of the
    // picture the fixed side gives way instead of the sign leaving the picture.
    (double fixed, double moving) axis(double fixed, double pointer, double minimum) {
      var moving = pointer.clamp(0.0, 1.0).toDouble();
      if ((moving - fixed).abs() < minimum) {
        moving = fixed + (moving >= fixed ? 1 : -1) * minimum;
        if (moving > 1) {
          moving = 1;
          fixed = 1 - minimum;
        } else if (moving < 0) {
          moving = 0;
          fixed = minimum;
        }
      }
      return (fixed, moving);
    }

    final x = axis(anchor.dx, to.dx, minSide / ZoneGeometry.refWidth);
    final y = axis(anchor.dy, to.dy, minSide / ZoneGeometry.refHeight);
    _setRect(s, Rect.fromPoints(Offset(x.$1, y.$1), Offset(x.$2, y.$2)));
    fit(s);
  }

  /// "21% x 21% of the picture": how big a sign is, in words.
  static String sizeText(Map<String, dynamic> s) {
    final w = (_n(s, 'w') / ZoneGeometry.refWidth * 100).round();
    final h = (_n(s, 'h') / ZoneGeometry.refHeight * 100).round();
    return '$w% x $h% of the picture';
  }

  /// The font size at which both lines fit in a box of [box] canvas pixels (the lines' widths are given at a font size of [at]).
  static double fontSizeFor(Size box, {required double widest, required double lineHeight, required double at}) =>
      math.min(box.width * 0.84 / widest, box.height * 0.30 / lineHeight) * at;
}
