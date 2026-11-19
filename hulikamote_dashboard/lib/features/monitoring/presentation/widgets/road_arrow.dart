import 'package:flutter/material.dart';

/// A line from [from] to [to] with an arrow head at [to]: the way traffic goes on a part of the road (incoming = toward the camera,
/// outgoing = away from it). Shared by the road editor and the live picture.
void paintRoadArrow(Canvas canvas, Offset from, Offset to, Color colour, {double width = 4, double head = 16}) {
  final line = Paint()
    ..color = colour
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;
  final v = to - from;
  final length = v.distance;
  if (length < 2) return;
  final dir = v / length;
  final size = head.clamp(6.0, length * 0.6);
  final normal = Offset(-dir.dy, dir.dx);
  final base = to - dir * size;
  canvas.drawLine(from, base, line);
  canvas.drawPath(
    Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(base.dx + normal.dx * size * 0.55, base.dy + normal.dy * size * 0.55)
      ..lineTo(base.dx - normal.dx * size * 0.55, base.dy - normal.dy * size * 0.55)
      ..close(),
    Paint()..color = colour..style = PaintingStyle.fill,
  );
}

/// An arrow that follows [points] (two or more): a bent road has a bent arrow, the head is at the last point.
void paintRoadPath(Canvas canvas, List<Offset> points, Color colour, {double width = 4, double head = 16}) {
  if (points.length < 2) return;
  if (points.length == 2) {
    paintRoadArrow(canvas, points[0], points[1], colour, width: width, head: head);
    return;
  }
  final line = Paint()
    ..color = colour
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(Path()..addPolygon(points, false), line);
  paintRoadArrow(canvas, points[points.length - 2], points.last, colour, width: width, head: head);   // the head (on the last piece)
}

/// The colour of a road area that has a direction: incoming (toward the camera) is blue, outgoing (away) is violet.
Color flowColour(String? flow) => switch (flow) {
  'in' => Colors.lightBlueAccent,
  'out' => Colors.purpleAccent,
  _ => Colors.lightBlueAccent,
};

/// "Incoming" / "Outgoing" for a road area's direction; null when it has none.
String? flowLabel(String? flow) => switch (flow) {
  'in' => 'Incoming',
  'out' => 'Outgoing',
  _ => null,
};
