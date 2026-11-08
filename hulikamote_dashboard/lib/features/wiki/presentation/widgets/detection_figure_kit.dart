import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours for the figures: a monochrome instrument palette, with the three
/// semantic colours reserved for meaning (pass, warn, fail) and one blue for
/// "the engine is looking at this".
class FigColors {
  final bool dark;
  const FigColors(this.dark);

  static const Color blue = Color(0xFF3B82F6);
  static const Color pass = Color(0xFF10B981);
  static const Color warn = Color(0xFFF59E0B);
  static const Color fail = Color(0xFFEF4444);

  Color get surface => dark ? const Color(0xFF0F141C) : Colors.white;
  Color get subtle => dark ? const Color(0xFF151C28) : const Color(0xFFF1F5F9);
  Color get line => dark ? const Color(0xFF1E2634) : const Color(0xFFE2E8F0);
  Color get road => dark ? const Color(0xFF121925) : const Color(0xFFE8EDF3);
  Color get text => dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  Color get sub => dark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  Color get mute => dark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
  Color get body => dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
}

/// A rectangle with a fixed aspect ratio, centred in the canvas, plus helpers
/// that place things by fraction so figures keep their shape at any width.
class Scene {
  final Rect r;
  const Scene(this.r);

  factory Scene.fit(Size size, [double aspect = 2.4]) {
    var w = size.width;
    var h = w / aspect;
    if (h > size.height) {
      h = size.height;
      w = h * aspect;
    }
    return Scene(Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h));
  }

  Offset p(double fx, double fy) => Offset(r.left + fx * r.width, r.top + fy * r.height);
  double w(double f) => f * r.width;
  double h(double f) => f * r.height;

  /// One "unit" = 1% of the scene height, for sizes that must not stretch.
  double get u => r.height / 100;
}

double clamp01(double v) => v.clamp(0.0, 1.0);

/// 0..1 progress of [t] between [a] and [b].
double seg(double t, double a, double b) => clamp01((t - a) / (b - a));

double ease(double x) => x * x * (3 - 2 * x);

double lerp(double a, double b, double x) => a + (b - a) * x;

/// Base class for every figure. [t] loops 0..1; [inputs] lists the extra values
/// that change what is drawn so the painter repaints when they change.
abstract class FigurePainter extends CustomPainter {
  FigurePainter(this.t, this.dark);

  final double t;
  final bool dark;

  FigColors get c => FigColors(dark);
  List<Object?> get inputs => const [];

  @override
  bool shouldRepaint(covariant FigurePainter old) =>
      old.runtimeType != runtimeType ||
      old.t != t ||
      old.dark != dark ||
      !listEquals(old.inputs, inputs);

  /// Draws the scene background and clips to it; returns the scene.
  Scene begin(Canvas canvas, Size size, {double aspect = 2.4}) {
    final s = Scene.fit(size, aspect);
    final rr = RRect.fromRectAndRadius(s.r, const Radius.circular(6));
    canvas.drawRRect(rr, Paint()..color = c.subtle);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = c.line
        ..style = PaintingStyle.stroke,
    );
    canvas.clipRRect(rr);
    return s;
  }
}

TextPainter _layout(
  String s,
  double size,
  Color color,
  FontWeight weight,
  bool mono,
  double? maxWidth,
) {
  final style = mono
      ? GoogleFonts.firaCode(fontSize: size, color: color, fontWeight: weight)
      : GoogleFonts.lexend(fontSize: size, color: color, fontWeight: weight);
  return TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);
}

/// Draws [s] with [anchor] as its left edge, or its centre / right edge.
void label(
  Canvas canvas,
  String s,
  Offset anchor,
  Color color, {
  double size = 10.5,
  FontWeight weight = FontWeight.w500,
  bool mono = false,
  TextAlign align = TextAlign.left,
  double? maxWidth,
}) {
  final tp = _layout(s, size, color, weight, mono, maxWidth);
  final dx = switch (align) {
    TextAlign.center => -tp.width / 2,
    TextAlign.right => -tp.width,
    _ => 0.0,
  };
  tp.paint(canvas, anchor + Offset(dx, -tp.height / 2));
}

/// A small filled tag, e.g. a confidence score or a verdict.
void tag(
  Canvas canvas,
  String s,
  Offset topLeft,
  Color bg,
  Color fg, {
  double size = 9.5,
}) {
  final tp = _layout(s, size, fg, FontWeight.w600, true, null);
  final rect = Rect.fromLTWH(topLeft.dx, topLeft.dy, tp.width + 8, tp.height + 4);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(3)),
    Paint()..color = bg,
  );
  tp.paint(canvas, topLeft + const Offset(4, 2));
}

Size tagSize(String s, {double size = 9.5}) {
  final tp = _layout(s, size, Colors.white, FontWeight.w600, true, null);
  return Size(tp.width + 8, tp.height + 4);
}

Paint stroke(Color color, [double width = 1.4]) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width;

Paint fill(Color color) => Paint()..color = color;

void dashedPath(Canvas canvas, Path path, Paint paint, {double dash = 5, double gap = 4}) {
  for (final m in path.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      d += dash + gap;
    }
  }
}

void dashedRect(Canvas canvas, Rect r, Color color, {double width = 1.2}) =>
    dashedPath(canvas, Path()..addRect(r), stroke(color, width));

/// A detection box, optionally with a tag above its top-left corner.
void detectionBox(
  Canvas canvas,
  Rect r,
  Color color, {
  String? text,
  Color? textColor,
  double width = 1.6,
  bool dashed = false,
  double tint = 0,
}) {
  if (tint > 0) canvas.drawRect(r, fill(color.withValues(alpha: tint)));
  if (dashed) {
    dashedRect(canvas, r, color, width: width);
  } else {
    canvas.drawRect(r, stroke(color, width));
  }
  if (text != null) {
    final sz = tagSize(text);
    tag(canvas, text, Offset(r.left, r.top - sz.height), color, textColor ?? Colors.white);
  }
}

void arrow(Canvas canvas, Offset a, Offset b, Color color, {double width = 1.6, double head = 6}) {
  canvas.drawLine(a, b, stroke(color, width));
  final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
  final p = Path()
    ..moveTo(b.dx, b.dy)
    ..lineTo(b.dx - head * math.cos(ang - 0.45), b.dy - head * math.sin(ang - 0.45))
    ..lineTo(b.dx - head * math.cos(ang + 0.45), b.dy - head * math.sin(ang + 0.45))
    ..close();
  canvas.drawPath(p, fill(color));
}

/// A top-down vehicle (bonnet towards -y when [up] is true).
void carTop(Canvas canvas, Rect r, FigColors c, {Color? body, bool up = true}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.22));
  canvas.drawRRect(rr, fill(body ?? c.body));
  canvas.drawRRect(rr, stroke(c.sub, 1));
  final glass = Rect.fromLTWH(
    r.left + r.width * 0.16,
    up ? r.top + r.height * 0.18 : r.bottom - r.height * 0.18 - r.height * 0.24,
    r.width * 0.68,
    r.height * 0.24,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(glass, Radius.circular(r.width * 0.1)),
    fill(c.surface.withValues(alpha: 0.85)),
  );
}

/// A top-down vehicle driving sideways ([right] = towards +x).
void carH(Canvas canvas, Rect r, FigColors c, {Color? body, bool right = true}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height * 0.28));
  canvas.drawRRect(rr, fill(body ?? c.body));
  canvas.drawRRect(rr, stroke(c.sub, 1));
  final glass = Rect.fromLTWH(
    right ? r.right - r.width * 0.38 : r.left + r.width * 0.14,
    r.top + r.height * 0.16,
    r.width * 0.24,
    r.height * 0.68,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(glass, Radius.circular(r.height * 0.12)),
    fill(c.surface.withValues(alpha: 0.85)),
  );
}

/// A vehicle seen from the front or rear.
void carFront(
  Canvas canvas,
  Rect r,
  FigColors c, {
  bool tinted = false,
  Color? glassTint,
  bool plate = true,
}) {
  final bodyR = RRect.fromRectAndRadius(r, Radius.circular(r.height * 0.14));
  canvas.drawRRect(bodyR, fill(c.body));
  canvas.drawRRect(bodyR, stroke(c.sub, 1));
  final glass = Rect.fromLTWH(r.left + r.width * 0.14, r.top + r.height * 0.1,
      r.width * 0.72, r.height * 0.4);
  canvas.drawRRect(
    RRect.fromRectAndRadius(glass, Radius.circular(r.height * 0.06)),
    fill(tinted ? const Color(0xFF0B0F17) : (glassTint ?? c.surface.withValues(alpha: 0.9))),
  );
  for (final fx in [0.12, 0.76]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + r.width * fx, r.top + r.height * 0.62, r.width * 0.12, r.height * 0.1),
        const Radius.circular(2),
      ),
      fill(c.mute),
    );
  }
  if (plate) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(r.center.dx, r.top + r.height * 0.84),
          width: r.width * 0.3,
          height: r.height * 0.13,
        ),
        const Radius.circular(2),
      ),
      fill(c.surface),
    );
  }
}

/// A standing person; [feet] is the ground point. A helmet is a cap over the head.
void person(
  Canvas canvas,
  Offset feet,
  double h,
  Color color, {
  Color? helmet,
}) {
  final p = stroke(color, math.max(1.4, h * 0.06));
  final head = Offset(feet.dx, feet.dy - h * 0.88);
  final r = h * 0.11;
  canvas.drawCircle(head, r, p);
  canvas.drawLine(Offset(feet.dx, feet.dy - h * 0.77), Offset(feet.dx, feet.dy - h * 0.38), p);
  canvas.drawLine(Offset(feet.dx - h * 0.16, feet.dy - h * 0.66),
      Offset(feet.dx + h * 0.16, feet.dy - h * 0.66), p);
  canvas.drawLine(Offset(feet.dx, feet.dy - h * 0.38), Offset(feet.dx - h * 0.12, feet.dy), p);
  canvas.drawLine(Offset(feet.dx, feet.dy - h * 0.38), Offset(feet.dx + h * 0.12, feet.dy), p);
  if (helmet != null) {
    canvas.drawArc(Rect.fromCircle(center: head, radius: r * 1.25), math.pi, math.pi, true,
        fill(helmet));
  }
}

/// A motorcycle in side view; [feet] is the ground point under the middle.
void moto(Canvas canvas, Offset center, double s, FigColors c) {
  final p = stroke(c.sub, math.max(1.4, s * 0.05));
  final wheel = s * 0.2;
  final back = Offset(center.dx - s * 0.32, center.dy - wheel);
  final front = Offset(center.dx + s * 0.32, center.dy - wheel);
  canvas.drawCircle(back, wheel, p);
  canvas.drawCircle(front, wheel, p);
  canvas.drawLine(back, Offset(center.dx - s * 0.02, center.dy - s * 0.42), p);
  canvas.drawLine(Offset(center.dx - s * 0.02, center.dy - s * 0.42), front, p);
  canvas.drawLine(Offset(center.dx + s * 0.18, center.dy - s * 0.46),
      Offset(center.dx + s * 0.3, center.dy - s * 0.55), p);
  canvas.drawLine(Offset(center.dx - s * 0.26, center.dy - s * 0.42),
      Offset(center.dx + s * 0.08, center.dy - s * 0.42), stroke(c.sub, s * 0.09));
}

/// A traffic light with one lit lamp.
void trafficLight(Canvas canvas, Offset topLeft, double h, String lit, FigColors c) {
  final w = h * 0.38;
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(topLeft.dx, topLeft.dy, w, h), Radius.circular(w * 0.2)),
    fill(c.dark ? const Color(0xFF0B0F17) : const Color(0xFF334155)),
  );
  const names = ['red', 'yellow', 'green'];
  const on = [FigColors.fail, FigColors.warn, FigColors.pass];
  for (var i = 0; i < 3; i++) {
    final centre = Offset(topLeft.dx + w / 2, topLeft.dy + h * (0.2 + 0.3 * i));
    canvas.drawCircle(
      centre,
      w * 0.3,
      fill(names[i] == lit ? on[i] : on[i].withValues(alpha: 0.18)),
    );
  }
}

/// A short filled progress ring.
void ring(Canvas canvas, Offset centre, double radius, double fraction, Color color, FigColors c) {
  canvas.drawCircle(centre, radius, stroke(c.line, 3));
  canvas.drawArc(
    Rect.fromCircle(center: centre, radius: radius),
    -math.pi / 2,
    2 * math.pi * clamp01(fraction),
    false,
    stroke(color, 3)..strokeCap = StrokeCap.round,
  );
}

/// A bar track with a coloured fill and an optional marker.
void barMeter(
  Canvas canvas,
  Rect r,
  double fraction,
  Color color,
  FigColors c, {
  double? marker,
}) {
  canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), fill(c.line));
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left, r.top, r.width * clamp01(fraction), r.height),
      const Radius.circular(3),
    ),
    fill(color),
  );
  if (marker != null) {
    final x = r.left + r.width * marker;
    canvas.drawLine(Offset(x, r.top - 3), Offset(x, r.bottom + 3), stroke(c.text, 1.2));
  }
}

/// Samples a polyline by arc length (0..1) and returns position and heading.
({Offset pos, double heading}) walk(List<Offset> pts, double f) {
  final lens = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    lens.add(lens.last + (pts[i] - pts[i - 1]).distance);
  }
  final target = clamp01(f) * lens.last;
  for (var i = 1; i < pts.length; i++) {
    if (target <= lens[i]) {
      final x = (target - lens[i - 1]) / (lens[i] - lens[i - 1]);
      final d = pts[i] - pts[i - 1];
      return (pos: pts[i - 1] + d * x, heading: math.atan2(d.dy, d.dx));
    }
  }
  final d = pts.last - pts[pts.length - 2];
  return (pos: pts.last, heading: math.atan2(d.dy, d.dx));
}

/// Hatched rectangle: how a blurred area is drawn in the figures.
void hatch(Canvas canvas, Rect r, Color color) {
  canvas.save();
  canvas.clipRect(r);
  final p = stroke(color, 1);
  for (var x = r.left - r.height; x < r.right; x += 4) {
    canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), p);
  }
  canvas.restore();
}

/// Smooth pulse 0..1..0 over [t] in [a]..[b].
double pulse(double t, double a, double b) {
  final x = seg(t, a, b);
  return math.sin(x * math.pi);
}

ui.Color mix(Color a, Color b, double x) => Color.lerp(a, b, clamp01(x))!;
