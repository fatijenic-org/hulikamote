import 'dart:math' as math;
import 'dart:ui' show Offset;

/// The same corners the backend paints a drawn crosswalk with (engine/crosswalk_overlay.py `quad_of`), so the editor shows the zebra as
/// it will look on the video: the four corners (far-left, far-right, near-right, near-left), or null when the shape is no area.
/// A shape of four corners keeps them; any other is boxed. The two LONG edges are the far and near one: the bars run across the short
/// side, side by side along the long one.
List<Offset>? zebraQuad(List<Offset> shape) {
  if (shape.length < 3) return null;
  var hull = _hull(shape);
  if (hull.length < 3) return null;
  if (hull.length != 4) hull = _box(hull);
  if (_area(hull).abs() < 4) return null;
  double edge(int i) => (hull[(i + 1) % 4] - hull[i]).distance;
  final start = edge(0) + edge(2) >= edge(1) + edge(3) ? 0 : 1;
  final a0 = hull[start], a1 = hull[(start + 1) % 4], b0 = hull[(start + 2) % 4], b1 = hull[(start + 3) % 4];
  var far = [a0, a1], near = [b1, b0]; // near[i] sits next to far[i]
  if (a0.dy + a1.dy > b0.dy + b1.dy) {
    far = [b1, b0];
    near = [a0, a1];
  }
  if (far[0].dx > far[1].dx) {
    far = [far[1], far[0]];
    near = [near[1], near[0]];
  }
  return [far[0], far[1], near[1], near[0]];
}

/// The white bars of a zebra: [stripes] four-corner shapes between the far and the near edge, side by side along the band.
List<List<Offset>> zebraBars(List<Offset> quad, {int stripes = 8, double fill = 0.58}) {
  final farLeft = quad[0], farRight = quad[1], nearRight = quad[2], nearLeft = quad[3];
  Offset lerp(Offset a, Offset b, double t) => a + (b - a) * t;
  return [
    for (var k = 0; k < stripes; k++)
      () {
        final u0 = (k + (1 - fill) / 2) / stripes, u1 = (k + 1 - (1 - fill) / 2) / stripes;
        return [lerp(farLeft, farRight, u0), lerp(farLeft, farRight, u1), lerp(nearLeft, nearRight, u1), lerp(nearLeft, nearRight, u0)];
      }(),
  ];
}

double _area(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final q = p[(i + 1) % p.length];
    a += p[i].dx * q.dy - q.dx * p[i].dy;
  }
  return a / 2;
}

/// Convex hull (monotone chain).
List<Offset> _hull(List<Offset> points) {
  final p = [...points]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double cross(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  final lower = <Offset>[];
  for (final q in p) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  final upper = <Offset>[];
  for (final q in p.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [...lower..removeLast(), ...upper..removeLast()];
}

/// The smallest turned box around a convex shape.
List<Offset> _box(List<Offset> hull) {
  List<Offset>? best;
  var bestArea = double.infinity;
  for (var i = 0; i < hull.length; i++) {
    final d = hull[(i + 1) % hull.length] - hull[i];
    final len = d.distance;
    if (len < 1e-6) continue;
    final u = d / len, v = Offset(-u.dy, u.dx);
    var minU = double.infinity, maxU = -double.infinity, minV = double.infinity, maxV = -double.infinity;
    for (final p in hull) {
      final pu = p.dx * u.dx + p.dy * u.dy, pv = p.dx * v.dx + p.dy * v.dy;
      minU = math.min(minU, pu);
      maxU = math.max(maxU, pu);
      minV = math.min(minV, pv);
      maxV = math.max(maxV, pv);
    }
    final area = (maxU - minU) * (maxV - minV);
    if (area < bestArea) {
      bestArea = area;
      best = [u * minU + v * minV, u * maxU + v * minV, u * maxU + v * maxV, u * minU + v * maxV];
    }
  }
  return best ?? hull.take(4).toList();
}
