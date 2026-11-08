import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../domain/models/scene_primitive.dart';
import '../../domain/palette/doc_palette.dart';

class DocScenePainter extends CustomPainter {
  final DocScene scene;
  final DocPalette palette;

  DocScenePainter({
    required this.scene,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (scene.w <= 0 || scene.h <= 0) return;
    final scaleX = size.width / scene.w;
    final scaleY = size.height / scene.h;
    // uniform scale preserving aspect ratio
    final scale = math.min(scaleX, scaleY);
    final offsetX = (size.width - scene.w * scale) / 2;
    final offsetY = (size.height - scene.h * scale) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale, scale);

    for (final p in scene.primitives) {
      _drawPrimitive(canvas, p);
    }

    canvas.restore();
  }

  void _drawPrimitive(Canvas canvas, DocPrimitive p) {
    switch (p) {
      case RectPrimitive():
        _drawRect(canvas, p);
      case LinePrimitive():
        _drawLine(canvas, p);
      case CirclePrimitive():
        _drawCircle(canvas, p);
      case PolygonPrimitive():
        _drawPolygon(canvas, p);
      case PolylinePrimitive():
        _drawPolyline(canvas, p);
      case PathPrimitive():
        _drawPath(canvas, p);
      case TextPrimitive():
        _drawText(canvas, p);
    }
  }

  void _drawRect(Canvas canvas, RectPrimitive p) {
    final rect = Rect.fromLTWH(p.x, p.y, p.w, p.h);
    final rrect = p.rx > 0
        ? RRect.fromRectAndRadius(rect, Radius.circular(p.rx))
        : RRect.fromRectAndRadius(rect, Radius.zero);

    Color? fillColor;
    Color? strokeColor;
    double strokeWidth = 1.3;

    final role = p.role;
    if (role == 'road') {
      fillColor = palette.colorMix(palette.ink, 0.08, palette.surface);
      strokeColor = palette.axis;
    } else if (role.startsWith('bx')) {
      final parts = role.split(' ');
      if (parts.length > 1) {
        final slot = parts[1];
        final col = palette.slotColor(slot);
        fillColor = palette.colorMix(col, 0.14, palette.surface);
        strokeColor = col;
      } else {
        fillColor = palette.surface;
        strokeColor = palette.axis;
      }
    } else if (role == 'veh') {
      fillColor = palette.colorMix(palette.s2, 0.22, palette.surface);
      strokeColor = palette.s2;
      strokeWidth = 2.0;
    } else if (role == 'per') {
      fillColor = palette.colorMix(palette.s7, 0.25, palette.surface);
      strokeColor = palette.s7;
      strokeWidth = 1.6;
    } else if (role == 'ok') {
      strokeColor = palette.good;
      strokeWidth = 2.4;
    } else if (role == 'no') {
      strokeColor = palette.crit;
      strokeWidth = 2.4;
    } else if (role == 'dark') {
      fillColor = const Color(0xFF222222);
    } else if (role == 'light') {
      fillColor = Colors.white;
    } else if (role == 'surface_box') {
      fillColor = palette.surface;
      strokeColor = palette.axis;
    } else if (role.startsWith('f')) {
      fillColor = palette.slotColor(role);
    } else {
      fillColor = palette.surface;
      strokeColor = palette.axis;
    }

    if (fillColor != null) {
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, fillPaint);
    }

    if (strokeColor != null) {
      final strokePaint = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      if (p.dash) {
        _drawDashedRRect(canvas, rrect, strokePaint);
      } else {
        canvas.drawRRect(rrect, strokePaint);
      }
    }
  }

  void _drawLine(Canvas canvas, LinePrimitive p) {
    Color strokeColor = palette.ink2;
    double sw = p.width;

    switch (p.role) {
      case 'a-ok':
        strokeColor = palette.good;
        sw = 3.2;
      case 'a-no':
        strokeColor = palette.crit;
        sw = 3.2;
      case 'a-in':
        strokeColor = palette.ink2;
        sw = 2.4;
      case 'path':
        strokeColor = palette.ink2;
        sw = 2.4;
      case 'ok':
        strokeColor = palette.good;
      case 'no':
        strokeColor = palette.crit;
      case 'axis':
        strokeColor = palette.axis;
        sw = 1.2;
      case 'grid':
        strokeColor = palette.grid;
        sw = 1.0;
      case 'target':
        strokeColor = palette.muted;
        sw = 1.2;
      case 'ar':
      default:
        strokeColor = palette.ink2;
        sw = 1.6;
    }

    final paint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;

    final p1 = Offset(p.x1, p.y1);
    final p2 = Offset(p.x2, p.y2);

    if (p.dash) {
      _drawDashedLine(canvas, p1, p2, paint);
    } else {
      canvas.drawLine(p1, p2, paint);
    }

    if (p.arrow) {
      _drawArrowHead(canvas, p1, p2, strokeColor);
    }
  }

  void _drawCircle(Canvas canvas, CirclePrimitive p) {
    Color? fillColor;
    Color? strokeColor;
    double sw = 1.6;

    switch (p.role) {
      case 'per':
        fillColor = palette.colorMix(palette.s7, 0.25, palette.surface);
        strokeColor = palette.s7;
      case 'zone':
        fillColor = p.fillSurface ? palette.surface : palette.colorMix(palette.s1, 0.18, Colors.transparent);
        strokeColor = palette.s1;
        sw = 2.0;
      case 'ok':
        fillColor = p.fillSurface ? palette.surface : Colors.transparent;
        strokeColor = palette.good;
        sw = 2.4;
      case 'no':
        fillColor = p.fillSurface ? palette.surface : Colors.transparent;
        strokeColor = palette.crit;
        sw = 2.4;
      case 'crit':
        fillColor = palette.crit;
      case 'warn':
        fillColor = palette.warn;
      case 'muted':
        fillColor = palette.muted;
      default:
        if (p.role.startsWith('f')) {
          fillColor = palette.slotColor(p.role);
        } else {
          fillColor = palette.surface;
          strokeColor = palette.axis;
        }
    }

    final center = Offset(p.cx, p.cy);
    if (fillColor != Colors.transparent) {
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, p.r, fillPaint);
    }

    if (strokeColor != null) {
      final strokePaint = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw;
      canvas.drawCircle(center, p.r, strokePaint);
    }
  }

  void _drawPolygon(Canvas canvas, PolygonPrimitive p) {
    if (p.points.isEmpty) return;
    final path = Path()..moveTo(p.points[0].dx, p.points[0].dy);
    for (var i = 1; i < p.points.length; i++) {
      path.lineTo(p.points[i].dx, p.points[i].dy);
    }
    path.close();

    Color? fillColor;
    Color? strokeColor;
    double sw = 1.6;

    switch (p.role) {
      case 'zone':
        fillColor = palette.colorMix(palette.s1, 0.18, Colors.transparent);
        strokeColor = palette.s1;
        sw = 2.0;
      case 'a-okh':
        fillColor = palette.good;
      case 'a-noh':
        fillColor = palette.crit;
      case 'a-inh':
      case 'ahp':
        fillColor = palette.ink2;
      default:
        fillColor = palette.surface;
        strokeColor = palette.axis;
    }

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    if (strokeColor != null) {
      final strokePaint = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw;
      canvas.drawPath(path, strokePaint);
    }
  }

  void _drawPolyline(Canvas canvas, PolylinePrimitive p) {
    if (p.points.isEmpty) return;
    final strokeColor = palette.ink2;
    final sw = 2.4;

    final paint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (p.dash) {
      for (var i = 0; i < p.points.length - 1; i++) {
        _drawDashedLine(canvas, p.points[i], p.points[i + 1], paint);
      }
    } else {
      final path = Path()..moveTo(p.points[0].dx, p.points[0].dy);
      for (var i = 1; i < p.points.length; i++) {
        path.lineTo(p.points[i].dx, p.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawPath(Canvas canvas, PathPrimitive p) {
    final parsed = _parseSvgPath(p.d);
    Color strokeColor = palette.ink2;
    Color? fillColor;
    double sw = p.width;

    switch (p.role) {
      case 'zone':
        fillColor = palette.colorMix(palette.s1, 0.18, Colors.transparent);
        strokeColor = palette.s1;
        sw = 2.0;
      case 'ok':
        strokeColor = palette.good;
        sw = 2.4;
      case 'no':
        strokeColor = palette.crit;
        sw = 2.4;
      case 'a-in':
        strokeColor = palette.ink2;
        sw = 2.4;
      case 'path':
      default:
        strokeColor = palette.ink2;
        sw = 2.4;
    }

    if (fillColor != null) {
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(parsed, fillPaint);
    }

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(parsed, strokePaint);
  }

  void _drawText(Canvas canvas, TextPrimitive p) {
    Color textColor = palette.ink2;
    double fontSize = 12.0;
    FontWeight fontWeight = FontWeight.normal;

    switch (p.role) {
      case 'bt':
        textColor = palette.ink;
        fontSize = 13.0;
        fontWeight = FontWeight.bold;
      case 'bs':
        textColor = palette.ink2;
        fontSize = 12.0;
      case 'yl':
      case 'al':
      case 'tl':
      case 'sk':
        textColor = palette.muted;
        fontSize = 11.5;
      case 'vl':
        textColor = palette.ink;
        fontSize = 12.0;
      case 'lg':
        textColor = palette.ink;
        fontSize = 12.5;
      default:
        textColor = palette.ink2;
        fontSize = 12.0;
    }

    final span = TextSpan(
      text: p.text,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: 'Segoe UI',
      ),
    );

    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    double dx = p.x;
    if (p.anchor == 'middle') {
      dx -= tp.width / 2;
    } else if (p.anchor == 'end') {
      dx -= tp.width;
    }
    // SVG text (x, y) baseline sits roughly 80% down the font box
    final dy = p.y - tp.height * 0.8;
    tp.paint(canvas, Offset(dx, dy));
  }

  Path _parseSvgPath(String d) {
    final path = Path();
    if (d.isEmpty) return path;

    // Tokens: command letters and numbers
    final re = RegExp(r'([a-zA-Z])|([+-]?(?:\d*\.\d+|\d+))');
    final matches = re.allMatches(d).toList();

    var i = 0;
    String currentCmd = 'M';
    double lastX = 0;
    double lastY = 0;

    while (i < matches.length) {
      final m = matches[i];
      final letter = m.group(1);
      if (letter != null) {
        currentCmd = letter;
        i++;
        if (currentCmd == 'Z' || currentCmd == 'z') {
          path.close();
        }
        continue;
      }

      // Read coordinates according to current command
      if (currentCmd == 'M' || currentCmd == 'm') {
        final x = double.parse(matches[i++].group(2)!);
        final y = double.parse(matches[i++].group(2)!);
        lastX = currentCmd == 'M' ? x : lastX + x;
        lastY = currentCmd == 'M' ? y : lastY + y;
        path.moveTo(lastX, lastY);
        currentCmd = currentCmd == 'M' ? 'L' : 'l';
      } else if (currentCmd == 'L' || currentCmd == 'l') {
        final x = double.parse(matches[i++].group(2)!);
        final y = double.parse(matches[i++].group(2)!);
        lastX = currentCmd == 'L' ? x : lastX + x;
        lastY = currentCmd == 'L' ? y : lastY + y;
        path.lineTo(lastX, lastY);
      } else if (currentCmd == 'V' || currentCmd == 'v') {
        final y = double.parse(matches[i++].group(2)!);
        lastY = currentCmd == 'V' ? y : lastY + y;
        path.lineTo(lastX, lastY);
      } else if (currentCmd == 'H' || currentCmd == 'h') {
        final x = double.parse(matches[i++].group(2)!);
        lastX = currentCmd == 'H' ? x : lastX + x;
        path.lineTo(lastX, lastY);
      } else if (currentCmd == 'Q' || currentCmd == 'q') {
        final x1 = double.parse(matches[i++].group(2)!);
        final y1 = double.parse(matches[i++].group(2)!);
        final x = double.parse(matches[i++].group(2)!);
        final y = double.parse(matches[i++].group(2)!);
        final c1X = currentCmd == 'Q' ? x1 : lastX + x1;
        final c1Y = currentCmd == 'Q' ? y1 : lastY + y1;
        lastX = currentCmd == 'Q' ? x : lastX + x;
        lastY = currentCmd == 'Q' ? y : lastY + y;
        path.quadraticBezierTo(c1X, c1Y, lastX, lastY);
      } else {
        i++; // skip unknown token
      }
    }

    return path;
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dist = (p2 - p1).distance;
    final unit = (p2 - p1) / (dist > 0 ? dist : 1.0);
    const dashLength = 6.0;
    const gapLength = 4.0;
    var current = 0.0;

    while (current < dist) {
      final start = p1 + unit * current;
      final len = math.min(dashLength, dist - current);
      final end = start + unit * len;
      canvas.drawLine(start, end, paint);
      current += dashLength + gapLength;
    }
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = math.min(5.0, metric.length - distance);
        final extract = metric.extractPath(distance, distance + len);
        canvas.drawPath(extract, paint);
        distance += 5.0 + 4.0;
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset p1, Offset p2, Color color) {
    final dir = p2 - p1;
    final angle = math.atan2(dir.dy, dir.dx);
    const arrowSize = 9.0;
    const arrowAngle = 0.45;

    final a1 = Offset(
      p2.dx - arrowSize * math.cos(angle - arrowAngle),
      p2.dy - arrowSize * math.sin(angle - arrowAngle),
    );
    final a2 = Offset(
      p2.dx - arrowSize * math.cos(angle + arrowAngle),
      p2.dy - arrowSize * math.sin(angle + arrowAngle),
    );

    final path = Path()
      ..moveTo(p2.dx, p2.dy)
      ..lineTo(a1.dx, a1.dy)
      ..lineTo(a2.dx, a2.dy)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DocScenePainter oldDelegate) {
    return oldDelegate.scene != scene || oldDelegate.palette != palette;
  }
}
