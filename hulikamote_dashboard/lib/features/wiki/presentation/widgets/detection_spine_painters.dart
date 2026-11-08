import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/detection_pipeline_rules.dart';
import 'detection_figure_kit.dart';

// Step 1 ─────────────────────────────────────────────────────────────────────

/// 1080p is shrunk to 720p, then only every third frame goes to the detector.
class FramesPainter extends FigurePainter {
  FramesPainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final w = s.r.width;
    final h = s.r.height;

    // Left: the shrink.
    final shrink = lerp(1, 0.667, ease(seg(t, 0.05, 0.3)));
    final bw = 0.2 * w * shrink;
    final bh = bw * 9 / 16;
    final centre = s.p(0.14, 0.42);
    final big = Rect.fromCenter(center: centre, width: bw, height: bh);
    canvas.drawRect(big, fill(c.surface));
    canvas.drawRect(big, stroke(FigColors.blue, 1.4));
    label(canvas, shrink > 0.84 ? '1080 px tall' : '720 px tall', s.p(0.14, 0.72), c.sub,
        size: 10, align: TextAlign.center, mono: true);
    label(canvas, 'scaled once, before anything else', s.p(0.14, 0.84), c.mute,
        size: 9.5, align: TextAlign.center, maxWidth: 0.26 * w);

    // Right: filmstrip.
    final fw = 0.058 * w;
    final fh = fw * 0.8;
    final gap = 0.014 * w;
    final left0 = s.r.left + 0.33 * w;
    final playhead = t * 9;
    final active = playhead.floor().clamp(0, 8);
    final rowY = s.r.top + 0.26 * h;
    final base = s.r.top + 0.93 * h;
    label(canvas, 'frames in', Offset(left0, s.r.top + 0.07 * h), c.mute, size: 9.5);
    label(canvas, 'cost per frame', Offset(left0, s.r.top + 0.52 * h), c.mute, size: 9.5);
    for (var i = 0; i < 9; i++) {
      final x = left0 + i * (fw + gap);
      final detect = i % 3 == 2;
      final r = Rect.fromLTWH(x, rowY - fh / 2, fw, fh);
      final lit = i == active;
      canvas.drawRect(r, fill(lit ? c.surface : c.subtle));
      canvas.drawRect(r, stroke(detect ? FigColors.blue : c.line, detect ? 1.6 : 1));
      final boxR = Rect.fromLTWH(r.left + fw * 0.2, r.top + fh * 0.3, fw * 0.4, fh * 0.45);
      if (detect) {
        canvas.drawRect(boxR, stroke(FigColors.blue, 1.2));
      } else {
        dashedRect(canvas, boxR, c.mute, width: 1);
      }
      label(canvas, detect ? 'detect' : 'redraw', Offset(r.center.dx, r.bottom + 9),
          detect ? FigColors.blue : c.mute,
          size: 8.5, align: TextAlign.center, mono: true);
      // cost bar
      final barH = detect ? 0.3 * h : math.max(2.0, 0.012 * h);
      final bar = Rect.fromLTWH(x + fw * 0.2, base - barH, fw * 0.6, barH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(2)),
        fill((detect ? FigColors.warn : FigColors.pass).withValues(alpha: lit ? 1 : 0.35)),
      );
      if (lit) {
        final tri = Path()
          ..moveTo(r.center.dx, r.top - 3)
          ..lineTo(r.center.dx - 4, r.top - 9)
          ..lineTo(r.center.dx + 4, r.top - 9)
          ..close();
        canvas.drawPath(tri, fill(c.text));
      }
    }
    label(canvas, '≈ 90 ms', Offset(left0 + 2 * (fw + gap) + fw * 1.25, base - 0.2 * h), FigColors.warn,
        size: 9.5, mono: true);
    label(canvas, '≈ 3 ms', Offset(left0 + 0 * (fw + gap) + fw * 0.2, base - 0.1 * h), FigColors.pass,
        size: 9.5, mono: true);
  }
}

// Step 2 ─────────────────────────────────────────────────────────────────────

class _DemoDetection {
  final String cls;
  final double conf;
  final Rect box; // fractions of the picture
  const _DemoDetection(this.cls, this.conf, this.box);
}

const List<_DemoDetection> _demo = [
  _DemoDetection('car', 0.91, Rect.fromLTWH(0.06, 0.52, 0.17, 0.32)),
  _DemoDetection('car', 0.78, Rect.fromLTWH(0.32, 0.40, 0.14, 0.26)),
  _DemoDetection('truck', 0.47, Rect.fromLTWH(0.20, 0.10, 0.17, 0.22)),
  _DemoDetection('car', 0.22, Rect.fromLTWH(0.46, 0.13, 0.09, 0.15)),
  _DemoDetection('motorcycle', 0.31, Rect.fromLTWH(0.58, 0.58, 0.09, 0.22)),
  _DemoDetection('person', 0.52, Rect.fromLTWH(0.59, 0.38, 0.05, 0.19)),
  _DemoDetection('bus', 0.62, Rect.fromLTWH(0.72, 0.14, 0.23, 0.30)),
  _DemoDetection('person', 0.38, Rect.fromLTWH(0.84, 0.58, 0.04, 0.18)),
];

class DetectorPainter extends FigurePainter {
  DetectorPainter(super.t, super.dark, {required this.cutoff});
  final double cutoff;

  @override
  List<Object?> get inputs => [cutoff];

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final frame = Rect.fromLTWH(s.r.left + 0.03 * s.r.width, s.r.top + 0.08 * s.r.height,
        0.58 * s.r.width, 0.84 * s.r.height);
    canvas.drawRect(frame, fill(c.road));
    canvas.drawRect(frame, stroke(c.line));
    final scan = seg(t, 0.0, 0.55);

    for (final d in _demo) {
      final r = Rect.fromLTWH(frame.left + d.box.left * frame.width, frame.top + d.box.top * frame.height,
          d.box.width * frame.width, d.box.height * frame.height);
      if (d.cls == 'person') {
        person(canvas, Offset(r.center.dx, r.bottom), r.height, c.sub);
      } else if (d.cls == 'motorcycle') {
        moto(canvas, Offset(r.center.dx, r.bottom), r.width * 1.6, c);
      } else {
        carTop(canvas, r.deflate(r.width * 0.12), c);
      }
      final shown = scan * frame.width > r.right - frame.left;
      if (!shown) continue;
      final keep = keepsDetection(cls: d.cls, confidence: d.conf, cutoff: cutoff);
      detectionBox(
        canvas,
        r,
        keep ? FigColors.blue : c.mute,
        text: '${d.cls} ${d.conf.toStringAsFixed(2)}${keep ? '' : ' dropped'}',
        dashed: !keep,
        width: keep ? 1.6 : 1.1,
      );
    }
    if (scan < 1) {
      final x = frame.left + frame.width * scan;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom),
          stroke(FigColors.blue.withValues(alpha: 0.7), 1.4));
    }

    // Letterbox inset.
    final sq = 0.34 * s.r.height * 1.4;
    final inset = Rect.fromLTWH(s.r.left + 0.66 * s.r.width, s.r.top + 0.08 * s.r.height, sq, sq);
    canvas.drawRect(inset, fill(const Color(0xFF727272).withValues(alpha: c.dark ? 0.55 : 0.4)));
    final ph = inset.width * 9 / 16;
    final pic = Rect.fromCenter(center: inset.center, width: inset.width, height: ph);
    canvas.drawRect(pic, fill(c.road));
    canvas.drawRect(inset, stroke(c.sub, 1));
    label(canvas, '640 × 640', Offset(inset.right + 8, inset.top + 8), c.text, size: 10, mono: true);
    label(canvas, 'grey padding 114', Offset(inset.right + 8, inset.top + 24), c.mute, size: 9.5, mono: true);
    label(canvas, 'aspect kept', Offset(inset.right + 8, inset.top + 40), c.mute, size: 9.5);

    // Confidence axis.
    final axis = Rect.fromLTWH(s.r.left + 0.66 * s.r.width, s.r.top + 0.80 * s.r.height,
        0.30 * s.r.width, 1);
    canvas.drawRect(axis, fill(c.sub));
    label(canvas, 'confidence', Offset(axis.left, axis.top - 38), c.mute, size: 9.5);
    label(canvas, '0', Offset(axis.left, axis.top + 10), c.mute, size: 9, mono: true);
    label(canvas, '1', Offset(axis.right, axis.top + 10), c.mute, size: 9, mono: true, align: TextAlign.right);
    for (final d in _demo) {
      final keep = keepsDetection(cls: d.cls, confidence: d.conf, cutoff: cutoff);
      final x = axis.left + axis.width * d.conf;
      canvas.drawCircle(Offset(x, axis.top - 8), 3.2, fill(keep ? FigColors.blue : c.mute));
    }
    final cx = axis.left + axis.width * cutoff;
    canvas.drawLine(Offset(cx, axis.top - 28), Offset(cx, axis.top + 4), stroke(FigColors.blue, 1.4));
    final mx = axis.left + axis.width * kMotorcycleCutoff;
    dashedPath(canvas, Path()..moveTo(mx, axis.top - 28)..lineTo(mx, axis.top + 4),
        stroke(FigColors.warn, 1.4));
    label(canvas, 'cutoff ${cutoff.toStringAsFixed(2)}', Offset(cx + 4, axis.top - 22), FigColors.blue,
        size: 9, mono: true);
    label(canvas, 'motorcycle 0.25', Offset(mx - 4, axis.top - 22), FigColors.warn,
        size: 9, mono: true, align: TextAlign.right);
  }
}

// Step 3 ─────────────────────────────────────────────────────────────────────

class ZoneFilterPainter extends FigurePainter {
  ZoneFilterPainter(super.t, super.dark);

  static const List<(double, double)> _zone = [
    (0.36, 0.06), (0.64, 0.06), (0.70, 0.94), (0.30, 0.94),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    for (final y in [0.5]) {
      canvas.drawRect(Rect.fromLTWH(s.r.left, s.r.top + y * s.r.height - 1, s.r.width, 2),
          fill(c.line));
    }
    final poly = Path()
      ..addPolygon([for (final p in _zone) s.p(p.$1, p.$2)], true);
    canvas.drawPath(poly, fill(FigColors.blue.withValues(alpha: 0.10)));
    dashedPath(canvas, poly, stroke(FigColors.blue, 1.4));
    label(canvas, 'drawn zone', s.p(0.5, 0.97), FigColors.blue, size: 9.5, align: TextAlign.center);

    const lanes = [0.26, 0.56, 0.82];
    const speeds = [1.0, 2.0, 1.0];
    const phases = [0.0, 0.35, 0.62];
    for (var i = 0; i < 3; i++) {
      for (final extra in [0.0, 0.5]) {
        final f = (t * speeds[i] + phases[i] + extra) % 1.0;
        final fx = lerp(-0.08, 1.08, f);
        final carW = s.w(0.09);
        final carH0 = s.h(0.13);
        final r = Rect.fromCenter(center: s.p(fx, lanes[i]), width: carW, height: carH0);
        final ground = Offset(r.center.dx, r.bottom);
        final inside = pointInPolygon(
          (ground.dx - s.r.left) / s.r.width,
          (ground.dy - s.r.top) / s.r.height,
          _zone,
        );
        carH(canvas, r, c, body: inside ? c.body : c.body.withValues(alpha: 0.4));
        if (inside) {
          detectionBox(canvas, r.inflate(2), FigColors.blue);
        } else {
          label(canvas, '×', Offset(r.center.dx, r.top - 6), c.mute, size: 11, align: TextAlign.center);
        }
        canvas.drawCircle(ground, 2.4, fill(inside ? FigColors.blue : c.mute));
      }
    }
    label(canvas, 'blue = kept for tracking', s.p(0.03, 0.06), FigColors.blue, size: 9.5);
    label(canvas, '× = dropped', s.p(0.03, 0.14), c.mute, size: 9.5);
  }
}

// Step 4 ─────────────────────────────────────────────────────────────────────

class TrackerPainter extends FigurePainter {
  TrackerPainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    for (final y in [0.32, 0.72]) {
      canvas.drawLine(s.p(0, y + 0.18), s.p(1, y + 0.18), stroke(c.line));
    }
    const hideFrom = 0.42;
    const hideTo = 0.60;
    final ax = lerp(0.06, 0.94, t);
    final aRect = Rect.fromCenter(center: s.p(ax, 0.32), width: s.w(0.11), height: s.h(0.17));
    final hidden = ax > hideFrom && ax < hideTo;

    // Car B, always visible.
    final bx = lerp(0.1, 0.9, (t * 0.6 + 0.3) % 1.0);
    final bRect = Rect.fromCenter(center: s.p(bx, 0.72), width: s.w(0.11), height: s.h(0.17));
    carH(canvas, bRect, c);
    detectionBox(canvas, bRect.inflate(2), FigColors.blue, text: '#9');

    carH(canvas, aRect, c);
    if (hidden) {
      dashedRect(canvas, aRect.inflate(2), FigColors.warn, width: 1.4);
      final missed = (seg(ax, hideFrom, hideTo) * 8).ceil().clamp(1, 8);
      tag(canvas, '#7 lost · kept ($missed of 60)', aRect.topLeft + const Offset(-6, -18),
          FigColors.warn, Colors.black);
    } else {
      detectionBox(canvas, aRect.inflate(2), FigColors.blue, text: '#7');
    }

    // The thing that hides it.
    final cover = Rect.fromLTRB(s.p(hideFrom + 0.03, 0).dx, s.p(0, 0.14).dy, s.p(hideTo - 0.03, 0).dx,
        s.p(0, 0.50).dy);
    canvas.drawRRect(RRect.fromRectAndRadius(cover, const Radius.circular(4)),
        fill(c.surface));
    canvas.drawRRect(RRect.fromRectAndRadius(cover, const Radius.circular(4)), stroke(c.line));
    label(canvas, 'bus in the way', cover.center, c.mute,
        size: 9, align: TextAlign.center, maxWidth: cover.width - 4);

    label(canvas, hidden ? 'detector cannot see #7: the tag waits' : 'tag #7 stays with the same car',
        s.p(0.03, 0.93), hidden ? FigColors.warn : c.sub, size: 10);
  }
}

// Step 5 ─────────────────────────────────────────────────────────────────────

class LedgerPainter extends FigurePainter {
  LedgerPainter(super.t, super.dark);

  static const List<Offset> _path = [
    Offset(0.06, 0.88), Offset(0.18, 0.72), Offset(0.30, 0.60), Offset(0.38, 0.40),
    Offset(0.30, 0.20), Offset(0.14, 0.12),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    // Trail scene (left half).
    final pts = [for (final p in _path) Offset(p.dx * 0.9, p.dy)];
    final cur = ease(seg(t, 0.0, 0.9));
    for (var i = 0; i < 24; i++) {
      final f = cur - i * 0.022;
      if (f < 0) break;
      final w = walk([for (final p in pts) s.p(p.dx, p.dy)], f);
      canvas.drawCircle(w.pos, math.max(1.2, 3.2 - i * 0.1),
          fill(FigColors.blue.withValues(alpha: math.max(0.08, 0.8 - i * 0.035))));
    }
    final head = walk([for (final p in pts) s.p(p.dx, p.dy)], cur);
    final carR = Rect.fromCenter(center: head.pos - Offset(0, s.h(0.08)), width: s.w(0.07), height: s.h(0.16));
    carTop(canvas, carR, c);
    detectionBox(canvas, carR.inflate(2), FigColors.blue, text: '#7');
    final ground = Offset(carR.center.dx, carR.bottom + 2);
    canvas.drawLine(ground + const Offset(-5, 0), ground + const Offset(5, 0), stroke(FigColors.warn, 1.6));
    canvas.drawLine(ground + const Offset(0, -5), ground + const Offset(0, 5), stroke(FigColors.warn, 1.6));
    label(canvas, 'ground point', ground + const Offset(8, 6), FigColors.warn, size: 9);
    label(canvas, 'path remembered', s.p(0.03, 0.06), c.mute, size: 9.5);

    // Diary card (right top).
    final looks = (t * 40).floor();
    final cls = looks < 5 ? 'unknown' : 'car';
    final speed = (110 + 40 * math.sin(t * math.pi * 2)).round();
    final rows = [
      ('track', '#7'),
      ('looks', '$looks'),
      ('type', cls),
      ('speed', '$speed px/s'),
      ('ground', '(${ground.dx.round()}, ${ground.dy.round()})'),
      ('suspected', 'nothing'),
    ];
    final card = Rect.fromLTWH(s.r.left + 0.50 * s.r.width, s.r.top + 0.07 * s.r.height,
        0.46 * s.r.width, 0.52 * s.r.height);
    canvas.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(4)), fill(c.surface));
    canvas.drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(4)), stroke(c.line));
    for (var i = 0; i < rows.length; i++) {
      final y = card.top + 12 + i * (card.height - 16) / rows.length;
      label(canvas, rows[i].$1, Offset(card.left + 10, y), c.mute, size: 9.5);
      label(canvas, rows[i].$2, Offset(card.left + card.width * 0.38, y),
          rows[i].$2 == 'unknown' ? FigColors.warn : c.text,
          size: 9.5, mono: true, maxWidth: card.width * 0.58);
    }

    // Stitch gates (right bottom).
    const gates = ['time', 'class', 'place', 'size', 'way', 'colour'];
    label(canvas, '#12 lost, #19 born: same car?', Offset(card.left, card.bottom + 14), c.sub, size: 9.5);
    final gw = (card.width - 5 * 5) / 6;
    final lit = seg(t, 0.15, 0.85) * (gates.length + 1);
    for (var i = 0; i < gates.length; i++) {
      final r = Rect.fromLTWH(card.left + i * (gw + 5), card.bottom + 26, gw, 20);
      final ok = lit > i + 0.5;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          fill(ok ? FigColors.pass.withValues(alpha: 0.2) : c.surface));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          stroke(ok ? FigColors.pass : c.line, 1));
      label(canvas, gates[i], r.center, ok ? FigColors.pass : c.mute,
          size: 8.5, align: TextAlign.center, mono: true, maxWidth: gw - 2);
    }
    if (lit > gates.length + 0.5) {
      label(canvas, 'all six pass → one diary', Offset(card.left, card.bottom + 58), FigColors.pass,
          size: 9.5, weight: FontWeight.w600);
    }
  }
}

// Step 7 figures ─────────────────────────────────────────────────────────────

/// A stopwatch that goes back to zero whenever the bad run is broken.
class HoldConfirmPainter extends FigurePainter {
  HoldConfirmPainter(super.t, super.dark, {required this.caption});
  final String caption;

  static const List<int> _cells = [
    0, 1, 1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0,
  ];
  static const int _need = 12;

  @override
  List<Object?> get inputs => [caption];

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size, aspect: 3.2);
    final n = _cells.length;
    final cursor = (seg(t, 0.02, 0.92) * n).floor().clamp(0, n - 1);
    var run = 0;
    for (var i = 0; i <= cursor; i++) {
      run = _cells[i] == 1 ? run + 1 : 0;
    }
    final cw = s.w(0.94) / n;
    final left = s.r.left + s.w(0.03);
    final top = s.r.top + s.h(0.18);
    label(canvas, 'each frame: does it look wrong?', Offset(left, s.r.top + s.h(0.08)), c.mute, size: 9.5);
    for (var i = 0; i < n; i++) {
      final r = Rect.fromLTWH(left + i * cw + 1, top, cw - 2, s.h(0.2));
      final seen = i <= cursor;
      final bad = _cells[i] == 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        fill(seen ? (bad ? FigColors.warn : c.line) : c.surface),
      );
      if (i == cursor) {
        canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(1.5), const Radius.circular(3)),
            stroke(c.text, 1.2));
      }
    }
    final flagged = run >= _need;
    final barR = Rect.fromLTWH(left, s.r.top + s.h(0.58), s.w(0.62), s.h(0.12));
    barMeter(canvas, barR, run / _need, flagged ? FigColors.fail : FigColors.blue, c);
    final brokeNow = cursor > 0 && _cells[cursor] == 0 && _cells[cursor - 1] == 1;
    label(canvas, 'stopwatch  $run of $_need steps', Offset(left, s.r.top + s.h(0.84)),
        flagged ? FigColors.fail : c.sub, size: 10, mono: true);
    if (brokeNow) {
      label(canvas, 'one good frame → back to 0', Offset(left + s.w(0.34), s.r.top + s.h(0.84)),
          c.mute, size: 9.5);
    }
    label(canvas, caption, Offset(s.r.right - s.w(0.03), s.r.top + s.h(0.84)), c.sub,
        size: 10, align: TextAlign.right);
    if (flagged) {
      tag(canvas, 'FLAGGED', Offset(barR.right + 12, barR.top - 3), FigColors.fail, Colors.white, size: 11);
    }
  }
}

/// A wobbling signal must pass a margin clearly, not just touch it.
class MarginConfirmPainter extends FigurePainter {
  MarginConfirmPainter(super.t, super.dark, {required this.caption});
  final String caption;

  @override
  List<Object?> get inputs => [caption];

  static double _v(double x) {
    if (x < 0.6) return 0.55 + 0.5 * math.sin(x * 9).abs();
    return 1.05 + 0.5 * seg(x, 0.6, 0.85);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size, aspect: 3.2);
    final plot = Rect.fromLTWH(s.r.left + s.w(0.04), s.r.top + s.h(0.12), s.w(0.60), s.h(0.74));
    double y(double v) => plot.bottom - v * plot.height / 1.7;
    // margin band
    final band = Rect.fromLTRB(plot.left, y(1.15), plot.right, y(1.0));
    canvas.drawRect(band, fill(FigColors.warn.withValues(alpha: 0.14)));
    canvas.drawLine(Offset(plot.left, y(1.0)), Offset(plot.right, y(1.0)), stroke(FigColors.warn, 1.2));
    canvas.drawLine(Offset(plot.left, y(1.15)), Offset(plot.right, y(1.15)), stroke(FigColors.fail, 1.2));
    label(canvas, 'the line', Offset(plot.right + 8, y(1.0)), FigColors.warn, size: 9.5);
    label(canvas, 'clearly past', Offset(plot.right + 8, y(1.15) - 8), FigColors.fail, size: 9.5);

    final x = seg(t, 0.03, 0.95);
    final path = Path();
    var started = false;
    for (var i = 0; i <= 120; i++) {
      final f = i / 120;
      if (f > x) break;
      final p = Offset(plot.left + f * plot.width, y(_v(f)));
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, stroke(FigColors.blue, 1.8));
    final v = _v(x);
    final tip = Offset(plot.left + x * plot.width, y(v));
    canvas.drawCircle(tip, 3.5, fill(FigColors.blue));
    final counted = v > 1.15;
    final text = counted
        ? 'clearly past → counted'
        : (v >= 1.0 ? 'touching the line → not counted' : 'short of the line');
    label(canvas, text, Offset(plot.right + 8, plot.bottom - 14),
        counted ? FigColors.fail : c.sub, size: 10, weight: counted ? FontWeight.w600 : FontWeight.w500);
    label(canvas, caption, Offset(plot.left, s.r.bottom - s.h(0.06)), c.mute, size: 9.5);
  }
}

/// A suspicion stays pending until the vehicle leaves, then it is decided.
class ExitConfirmPainter extends FigurePainter {
  ExitConfirmPainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size, aspect: 3.0);
    final phase = t < 0.5 ? 0 : 1;
    final local = phase == 0 ? t / 0.5 : (t - 0.5) / 0.5;
    final move = seg(local, 0.0, 0.62);
    final decided = local > 0.7;

    final laneY = 0.5;
    canvas.drawLine(s.p(0.03, laneY + 0.2), s.p(0.70, laneY + 0.2), stroke(c.line));
    // door
    canvas.drawLine(s.p(0.72, 0.18), s.p(0.72, 0.82), stroke(c.sub, 1.6));
    label(canvas, 'leaves the picture', s.p(0.72, 0.1), c.mute, size: 9.5, align: TextAlign.center);

    final carRect = Rect.fromCenter(
        center: s.p(lerp(0.1, 0.68, move), laneY), width: s.w(0.09), height: s.h(0.2));
    final foundAt = phase == 1 ? 0.30 : 2.0; // scenario B finds a plate part way
    final plateFound = move >= foundAt;
    carH(canvas, carRect, c);
    final pending = phase == 0 ? move > 0.35 : (move > 0.2 && !plateFound);
    final box = decided
        ? (phase == 0 ? FigColors.fail : FigColors.pass)
        : (plateFound ? FigColors.pass : (pending ? FigColors.warn : FigColors.blue));
    detectionBox(canvas, carRect.inflate(2), box,
        text: plateFound
            ? 'plate found'
            : (pending ? 'NO PLATE SEEN YET' : 'looking…'),
        textColor: Colors.black);

    label(canvas, phase == 0 ? 'vehicle A: never shows a plate' : 'vehicle B: a plate shows up later',
        s.p(0.03, 0.08), c.sub, size: 10);

    // Outcomes
    final outA = Rect.fromLTWH(s.p(0.77, 0).dx, s.p(0, 0.2).dy, s.w(0.2), s.h(0.28));
    final outB = Rect.fromLTWH(s.p(0.77, 0).dx, s.p(0, 0.56).dy, s.w(0.2), s.h(0.28));
    for (final (r, on, col, text) in [
      (outA, decided && phase == 0, FigColors.fail, 'no_plate ticket'),
      (outB, decided && phase == 1, FigColors.pass, 'cleared · photos deleted'),
    ]) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
          fill(on ? col.withValues(alpha: 0.18) : c.surface));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
          stroke(on ? col : c.line, 1.2));
      label(canvas, text, r.center, on ? col : c.mute,
          size: 9.5, align: TextAlign.center, maxWidth: r.width - 8, weight: on ? FontWeight.w600 : FontWeight.w500);
    }
  }
}

// Step 8 ─────────────────────────────────────────────────────────────────────

class EvidencePainter extends FigurePainter {
  EvidencePainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final frame = Rect.fromLTWH(s.r.left + 0.03 * s.r.width, s.r.top + 0.08 * s.r.height,
        0.58 * s.r.width, 0.84 * s.r.height);
    canvas.drawRect(frame, fill(c.road));
    canvas.drawRect(frame, stroke(c.line));
    final sweep = seg(t, 0.25, 0.55);
    final sweepX = frame.left + frame.width * sweep;
    bool blurred(double x) => sweep > 0 && x < sweepX;

    // violator (kept sharp)
    final v = Rect.fromLTWH(frame.left + frame.width * 0.10, frame.top + frame.height * 0.34,
        frame.width * 0.30, frame.height * 0.52);
    carFront(canvas, v, c, plate: true);
    final vPlate = Rect.fromCenter(
        center: Offset(v.center.dx, v.top + v.height * 0.84), width: v.width * 0.3, height: v.height * 0.13);
    // other vehicle
    final o = Rect.fromLTWH(frame.left + frame.width * 0.56, frame.top + frame.height * 0.40,
        frame.width * 0.26, frame.height * 0.46);
    carFront(canvas, o, c, plate: true);
    final oPlate = Rect.fromCenter(
        center: Offset(o.center.dx, o.top + o.height * 0.84), width: o.width * 0.3, height: o.height * 0.13);
    if (blurred(oPlate.right)) hatch(canvas, oPlate.inflate(1), c.sub);
    // pedestrian head
    final feet = Offset(frame.left + frame.width * 0.47, frame.bottom - frame.height * 0.06);
    final ph = frame.height * 0.5;
    person(canvas, feet, ph, c.sub);
    final head = Rect.fromCircle(center: Offset(feet.dx, feet.dy - ph * 0.88), radius: ph * 0.14);
    if (blurred(head.right)) hatch(canvas, head, c.sub);

    if (sweep > 0 && sweep < 1) {
      canvas.drawLine(Offset(sweepX, frame.top), Offset(sweepX, frame.bottom),
          stroke(FigColors.blue.withValues(alpha: 0.7), 1.4));
    }
    if (sweep >= 1) {
      detectionBox(canvas, vPlate.inflate(2), FigColors.pass);
      label(canvas, 'kept sharp', Offset(vPlate.center.dx, vPlate.bottom + 12), FigColors.pass,
          size: 9, align: TextAlign.center);
      label(canvas, 'blurred', Offset(oPlate.center.dx, oPlate.bottom + 12), c.mute,
          size: 9, align: TextAlign.center);
    }
    final marks = seg(t, 0.6, 0.72);
    if (marks > 0) {
      detectionBox(canvas, v.inflate(3), FigColors.fail, text: 'REASON BOX', width: 1.8);
    }

    // Frame strip and saved files.
    final left0 = s.r.left + 0.66 * s.r.width;
    final cw = (0.30 * s.r.width) / 12;
    label(canvas, 'frames of a flagged car', Offset(left0, s.r.top + 0.10 * s.r.height), c.mute, size: 9.5);
    const saved = {1, 5, 10};
    final nowFrame = (seg(t, 0.0, 0.95) * 12).floor() + 1;
    for (var i = 1; i <= 12; i++) {
      final r = Rect.fromLTWH(left0 + (i - 1) * cw + 1, s.r.top + 0.18 * s.r.height, cw - 2, 0.18 * s.r.height);
      final on = saved.contains(i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        fill(on && i <= nowFrame ? FigColors.pass : (i <= nowFrame ? c.line : c.surface)),
      );
    }
    label(canvas, 'saved: 1st, then every 5th', Offset(left0, s.r.top + 0.45 * s.r.height), FigColors.pass,
        size: 9.5);
    const files = ['annotated photo', 'clean vehicle crop', 'wider clean crop'];
    for (var i = 0; i < files.length; i++) {
      final appear = seg(t, 0.72 + i * 0.07, 0.8 + i * 0.07);
      final r = Rect.fromLTWH(left0, s.r.top + (0.56 + i * 0.13) * s.r.height, 0.30 * s.r.width, 0.10 * s.r.height);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          fill(c.surface.withValues(alpha: appear)));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          stroke(c.line.withValues(alpha: appear), 1));
      label(canvas, files[i], r.center, c.text.withValues(alpha: appear),
          size: 9.5, align: TextAlign.center, maxWidth: r.width - 6);
    }
  }
}

// Step 9 ─────────────────────────────────────────────────────────────────────

class TicketPainter extends FigurePainter {
  TicketPainter(super.t, super.dark);

  static const _raws = ['A8C1Z34', 'ABC1234', 'A8C1234', 'ABG1234'];

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);

    // Row 1: sharpen.
    final y1 = 0.17;
    final small = Rect.fromCenter(center: s.p(0.10, y1), width: s.w(0.09), height: s.h(0.1));
    final big = Rect.fromCenter(center: s.p(0.34, y1), width: s.w(0.22), height: s.h(0.2));
    for (final (r, txt, sz, a) in [(small, 'ABC 1234', 7.0, 0.7), (big, 'ABC 1234', 17.0, 1.0)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), fill(c.surface));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), stroke(c.line));
      label(canvas, txt, r.center, c.text.withValues(alpha: a),
          size: sz, mono: true, align: TextAlign.center, weight: FontWeight.w600);
    }
    arrow(canvas, s.p(0.17, y1), s.p(0.21, y1), c.sub);
    label(canvas, 'crop', s.p(0.10, y1 + 0.13), c.mute, size: 9, align: TextAlign.center);
    label(canvas, 'sharpened ×4', s.p(0.34, y1 + 0.17), c.mute, size: 9, align: TextAlign.center);
    label(canvas, 'up to 40 crops per ticket', s.p(0.62, y1), c.sub, size: 10);

    // Row 2: one OCR read, fixed by slot.
    final raw = _raws[0];
    final fixed = cleanPhPlate(raw);
    final y2 = 0.52;
    final cell = s.w(0.052);
    final x0 = s.p(0.06, 0).dx;
    label(canvas, 'OCR read', Offset(x0, s.p(0, y2 - 0.13).dy), c.mute, size: 9.5);
    final fixPhase = seg(t, 0.28, 0.5);
    for (var i = 0; i < raw.length; i++) {
      final isLetterSlot = i <= 2;
      final slotColour = isLetterSlot ? FigColors.blue : FigColors.warn;
      final changed = raw[i] != fixed[i];
      final r = Rect.fromLTWH(x0 + i * (cell + 4), s.p(0, y2 - 0.07).dy, cell, s.h(0.14));
      final flash = changed && fixPhase > 0 && fixPhase < 1;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          fill(flash ? FigColors.fail.withValues(alpha: 0.25) : c.surface));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          stroke(changed && fixPhase > 0 ? FigColors.fail : c.line));
      final shown = (changed && fixPhase >= 1) ? fixed[i] : raw[i];
      label(canvas, shown, r.center, c.text, size: 12, mono: true, align: TextAlign.center,
          weight: FontWeight.w600);
      label(canvas, isLetterSlot ? 'letter' : 'digit',
          Offset(r.center.dx, r.bottom + 9), slotColour, size: 8.5, align: TextAlign.center, mono: true);
    }
    label(canvas, fixPhase >= 1 ? '8 → B and Z → 2: wrong kind of character for the slot' : 'checking each slot…',
        Offset(x0 + 7 * (cell + 4) + 10, s.p(0, y2).dy), fixPhase >= 1 ? FigColors.fail : c.mute,
        size: 9.5);

    // Row 3: crops vote.
    final y3 = 0.86;
    label(canvas, 'crops vote', Offset(x0, s.p(0, y3 - 0.1).dy), c.mute, size: 9.5);
    final votes = [for (final r in _raws) cleanPhPlate(r)];
    final voteShown = seg(t, 0.55, 0.9) * votes.length;
    for (var i = 0; i < votes.length; i++) {
      final r = Rect.fromLTWH(x0 + i * s.w(0.15), s.p(0, y3 - 0.04).dy, s.w(0.14), s.h(0.12));
      final on = voteShown > i;
      final win = votes[i] == 'ABC1234';
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          fill(on ? (win ? FigColors.pass.withValues(alpha: 0.18) : c.line) : c.surface));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          stroke(on && win ? FigColors.pass : c.line));
      label(canvas, on ? votes[i] : '', r.center, c.text, size: 9.5, mono: true, align: TextAlign.center);
    }
    if (voteShown >= votes.length) {
      tag(canvas, 'ABC1234 · 3 of 4 votes', Offset(x0 + 4 * s.w(0.15) + 6, s.p(0, y3 - 0.03).dy),
          FigColors.pass, Colors.black, size: 10.5);
    }
  }
}
