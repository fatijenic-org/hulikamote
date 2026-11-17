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
