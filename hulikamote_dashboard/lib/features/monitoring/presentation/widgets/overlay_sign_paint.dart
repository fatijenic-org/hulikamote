import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../forensic/data/object_previews.dart';
import '../../../forensic/domain/lane_signs.dart';
import '../../../forensic/domain/loading_signs.dart';
import '../../../forensic/domain/zone_geometry.dart';
import '../../../forensic/presentation/widgets/box_object.dart';

/// The overlay signs as the Forensic zone editor draws them (same drawing: widgets/zone_editor.dart `_sign` and `_boxObject`, without the
/// handles used for editing), so the Live Monitor's setup shows the same pictures.

/// A lane sign (Restricted lane): the blue board with its two lines, on its pole or tripod, turned and tilted as set. [at] is the board's
/// middle in pixels of [size].
void paintLaneBoard(
  Canvas canvas,
  Size size, {
  required Offset at,
  required LaneSign spec,
  double scale = 1,
  double angle = 0,
  double tilt = 0,
  String stand = 'none',
}) {
  final w = SignGeometry.width(size, scale), h = SignGeometry.height(size, scale);
  if (stand != 'none') {
    // the pole or tripod goes straight down from the board to the ground, like the backend draws it
    final top = Offset(at.dx, at.dy + h / 2), foot = top + Offset(0, 1.5 * w);
    final metal = Paint()
      ..color = const Color(0xFF969899)
      ..strokeWidth = math.max(2.0, w * 0.06)
      ..strokeCap = StrokeCap.round;
    if (stand == 'tripod') {
      final knee = top + Offset(0, 0.82 * w);
      canvas.drawLine(top, knee, metal);
      canvas.drawLine(knee, foot + Offset(-0.36 * w, 0), metal);
      canvas.drawLine(knee, foot + Offset(0.36 * w, 0), metal);
    } else {
      canvas.drawLine(top, foot, metal);
      canvas.drawLine(foot + Offset(-0.14 * w, 0), foot + Offset(0.14 * w, 0), metal);
    }
  }
  canvas.save();
  canvas.translate(at.dx, at.dy);
  final m = Matrix4.identity()..rotateZ(angle * math.pi / 180);
  m.multiply(Matrix4.identity()..setEntry(3, 2, 1 / (3 * w)));
  m.rotateY(-tilt * math.pi / 180);
  canvas.transform(m.storage);
  final board = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(w / 22));
  canvas.drawRRect(board.shift(Offset(w * 0.045, w * 0.07)), Paint()..color = Colors.black38);
  canvas.drawRRect(board, Paint()..color = const Color(0xFF0A4696));
  canvas.drawRRect(board.deflate(w / 28), Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = math.max(1.0, w / 40));
  final lines = [spec.line1, spec.line2];
  final probe = TextPainter(
    text: TextSpan(text: lines.reduce((a, b) => a.length >= b.length ? a : b), style: TextStyle(fontSize: h * 0.3, fontWeight: FontWeight.w600)),
    textDirection: TextDirection.ltr,
  )..layout();
  final fontSize = h * 0.3 * math.min(1.0, (w * 0.8) / math.max(probe.width, 1));
  for (var i = 0; i < 2; i++) {
    final tp = TextPainter(
      text: TextSpan(text: lines[i], style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, (i == 0 ? -h * 0.22 : h * 0.18) - tp.height / 2));
  }
  canvas.restore();
}

/// A box of Illegal parking / loading and the like: the banned area as a faint tinted patch with a dashed edge, and the object that stands
/// in it (the picture the backend drew, hydrant, sign on a pole ...). While that picture is on its way a dot marks the spot.
void paintBoxPicture(Canvas canvas, Size size, BoxObject s) {
  Offset px(Offset n) => Offset(n.dx * size.width, n.dy * size.height);
  final ring = [for (final p in s.polygon) px(p)];
  final tint = LoadingSigns.tintOf(s.kind);
  canvas.drawPath(Path()..addPolygon(ring, true), Paint()..color = tint.withValues(alpha: 0.14));
  final dash = Paint()
    ..color = Colors.white.withValues(alpha: 0.9)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i], b = ring[(i + 1) % ring.length];
    final length = (b - a).distance;
    if (length == 0) continue;
    for (var d = 0.0; d < length; d += 16) {
      canvas.drawLine(a + (b - a) * (d / length), a + (b - a) * (math.min(d + 8, length) / length), dash);
    }
  }
  final at = px(s.at);
  final p = s.preview;
  if (p != null) {
    final k = size.width / ZoneGeometry.refWidth; // the picture was made for a frame 1920 wide
    canvas.drawImageRect(
      p.image,
      Rect.fromLTWH(0, 0, p.image.width.toDouble(), p.image.height.toDouble()),
      Rect.fromLTWH(at.dx + p.dx * k, at.dy + p.dy * k, p.image.width * k, p.image.height * k),
      Paint()..filterQuality = FilterQuality.medium,
    );
  } else {
    canvas.drawCircle(at, 6, Paint()..color = tint);
  }
}

/// Road paint along a line (a painted solid line): the picture the backend drew, in place.
void paintLinePicture(Canvas canvas, Size size, ObjectPreview p) {
  final k = size.width / ZoneGeometry.refWidth;
  canvas.drawImageRect(
    p.image,
    Rect.fromLTWH(0, 0, p.image.width.toDouble(), p.image.height.toDouble()),
    Rect.fromLTWH(p.dx * k, p.dy * k, p.image.width * k, p.image.height * k),
    Paint()..filterQuality = FilterQuality.medium,
  );
}
