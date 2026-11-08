import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/detection_pipeline_rules.dart';
import 'detection_figure_kit.dart';

// Zone rules ─────────────────────────────────────────────────────────────────

/// Inside the zone and slower than 25 px/s starts a stopwatch.
class StoppedPainter extends FigurePainter {
  StoppedPainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final zone = Rect.fromLTRB(s.p(0.30, 0).dx, s.p(0, 0.46).dy, s.p(0.78, 0).dx, s.p(0, 0.82).dy);
    canvas.drawRect(zone, fill(FigColors.blue.withValues(alpha: 0.10)));
    dashedRect(canvas, zone, FigColors.blue, width: 1.4);
    label(canvas, 'no-parking zone', Offset(zone.left + 4, zone.top - 8), FigColors.blue, size: 9.5);

    // Car B drives straight through the far lane.
    final bx = lerp(-0.1, 1.1, (t * 1.0) % 1.0);
    final bRect = Rect.fromCenter(center: s.p(bx, 0.27), width: s.w(0.1), height: s.h(0.15));
    carH(canvas, bRect, c);
    label(canvas, 'passing through: no clock', s.p(0.03, 0.10), c.mute, size: 9.5);

    // Car A slows and stops in the zone.
    final drive = ease(seg(t, 0.02, 0.30));
    final ax = lerp(0.04, 0.52, drive);
    final aRect = Rect.fromCenter(center: s.p(ax, 0.64), width: s.w(0.1), height: s.h(0.15));
    final speed = t < 0.30 ? 170 * (1 - drive) : 4 + 3 * math.sin(t * 40).abs();
    final inside = zone.contains(Offset(aRect.center.dx, aRect.bottom));
    final stopped = speed < 25;
    final watch = inside && stopped ? seg(t, 0.32, 0.84) : 0.0;
    final flagged = watch >= 1;
    carH(canvas, aRect, c);
    detectionBox(canvas, aRect.inflate(2), flagged ? FigColors.fail : FigColors.blue,
        text: flagged ? 'ILLEGAL PARKING' : '#7');

    // Speed meter.
    final meter = Rect.fromLTWH(s.p(0.04, 0).dx, s.p(0, 0.93).dy, s.w(0.32), 6);
    barMeter(canvas, meter, speed / 200, stopped ? FigColors.pass : FigColors.warn, c, marker: 25 / 200);
    label(canvas, 'speed ${speed.round()} px/s', Offset(meter.left, meter.top - 12), c.sub, size: 9.5, mono: true);
    label(canvas, '25 = “stopped”', Offset(meter.left + meter.width * 0.125 + 4, meter.top + 15),
        c.mute, size: 8.5, mono: true);

    // Stopwatch ring.
    final centre = s.p(0.90, 0.36);
    ring(canvas, centre, 17, watch, flagged ? FigColors.fail : FigColors.blue, c);
    label(canvas, watch == 0 ? 'idle' : (flagged ? 'limit' : 'timing'), centre + const Offset(0, 30),
        c.sub, size: 9, align: TextAlign.center);
  }
}

/// A heading dial: more than 135° off the legal arrow, held, is wrong-way.
class WrongWayPainter extends FigurePainter {
  WrongWayPainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final lane = Rect.fromLTRB(s.p(0.10, 0).dx, s.r.top, s.p(0.50, 0).dx, s.r.bottom);
    canvas.drawRect(lane, fill(FigColors.blue.withValues(alpha: 0.08)));
    dashedRect(canvas, lane, FigColors.blue, width: 1.2);
    arrow(canvas, s.p(0.30, 0.10), s.p(0.30, 0.34), FigColors.pass, width: 2.2, head: 8);
    label(canvas, 'legal direction', s.p(0.30, 0.42), FigColors.pass, size: 9.5, align: TextAlign.center);

    final legalY = lerp(-0.12, 1.12, (t * 1.0 + 0.30) % 1.0);
    final legal = Rect.fromCenter(center: s.p(0.19, legalY), width: s.w(0.06), height: s.h(0.2));
    carTop(canvas, legal, c, up: false);
    final wrongY = lerp(1.12, -0.12, t % 1.0);
    final wrong = Rect.fromCenter(center: s.p(0.41, wrongY), width: s.w(0.06), height: s.h(0.2));
    carTop(canvas, wrong, c);

    // Dial.
    final centre = s.p(0.78, 0.50);
    final radius = s.h(0.30);
    final wedge = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawCircle(centre, radius, fill(c.surface));
    canvas.drawArc(wedge, 5 * math.pi / 4, math.pi / 2, true, fill(FigColors.fail.withValues(alpha: 0.22)));
    canvas.drawCircle(centre, radius, stroke(c.line, 1.2));
    arrow(canvas, centre, centre + Offset(0, radius * 0.85), FigColors.pass, width: 1.8);
    final jitter = 0.05 * math.sin(t * 30);
    final head = -math.pi / 2 + jitter;
    arrow(canvas, centre, centre + Offset(math.cos(head), math.sin(head)) * radius * 0.9,
        FigColors.blue, width: 2.2);
    label(canvas, 'more than 135° off', centre + Offset(0, -radius - 12), FigColors.fail,
        size: 9.5, align: TextAlign.center);
    label(canvas, 'its heading', centre + Offset(0, radius + 12), FigColors.blue,
        size: 9.5, align: TextAlign.center);

    final held = seg(t, 0.22, 0.80);
    final bar = Rect.fromLTWH(s.p(0.60, 0).dx, s.p(0, 0.94).dy, s.w(0.34), 6);
    barMeter(canvas, bar, held, held >= 1 ? FigColors.fail : FigColors.blue, c);
    label(canvas, 'against it for ${(held * 1.5).toStringAsFixed(1)} s of 1.5 s',
        Offset(bar.left, bar.top - 12), c.sub, size: 9.5, mono: true);
    detectionBox(canvas, wrong.inflate(2), held >= 1 ? FigColors.fail : FigColors.blue,
        text: held >= 1 ? 'COUNTERFLOW' : '#4');
  }
}

/// Heading at entry versus heading now: a swing of 45° or more along the arrow.
class WrongTurnPainter extends FigurePainter {
  WrongTurnPainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    // roads
    canvas.drawRect(Rect.fromLTRB(s.p(0.34, 0).dx, s.p(0, 0.40).dy, s.p(0.46, 0).dx, s.r.bottom), fill(c.road));
    canvas.drawRect(Rect.fromLTRB(s.r.left, s.p(0, 0.36).dy, s.p(0.46, 0).dx, s.p(0, 0.54).dy), fill(c.road));
    final zone = Rect.fromLTRB(s.p(0.22, 0).dx, s.p(0, 0.24).dy, s.p(0.58, 0).dx, s.p(0, 0.78).dy);
    dashedRect(canvas, zone, FigColors.blue, width: 1.3);
    label(canvas, 'no left turn here', Offset(zone.left, zone.top - 8), FigColors.blue, size: 9.5);
    arrow(canvas, s.p(0.30, 0.15), s.p(0.14, 0.15), FigColors.fail, width: 2, head: 8);
    label(canvas, 'forbidden direction', s.p(0.14, 0.07), FigColors.fail, size: 9.5);

    final pts = [
      s.p(0.40, 1.02), s.p(0.40, 0.72), s.p(0.40, 0.58), s.p(0.37, 0.48), s.p(0.30, 0.45), s.p(0.10, 0.45),
    ];
    final f = ease(seg(t, 0.04, 0.82));
    final w = walk(pts, f);
    final entry = pts[1];
    arrow(canvas, entry, entry + const Offset(0, -34), c.mute, width: 1.6);
    label(canvas, 'heading at entry', entry + const Offset(8, -4), c.mute, size: 9);

    canvas.save();
    canvas.translate(w.pos.dx, w.pos.dy);
    canvas.rotate(w.heading + math.pi / 2);
    carTop(canvas, Rect.fromCenter(center: Offset.zero, width: s.w(0.055), height: s.h(0.2)), c);
    canvas.restore();
    arrow(canvas, w.pos, w.pos + Offset(math.cos(w.heading), math.sin(w.heading)) * 38,
        FigColors.blue, width: 2);

    // swing readout
    final entryHeading = -math.pi / 2;
    var swing = (w.heading - entryHeading).abs() * 180 / math.pi;
    if (swing > 180) swing = 360 - swing;
    var toArrow = (w.heading - math.pi).abs() * 180 / math.pi;
    if (toArrow > 180) toArrow = 360 - toArrow;
    final flagged = swing >= 45 && toArrow <= 45 && f > 0.6;
    label(canvas, 'swing ${swing.round()}° (needs 45°)', s.p(0.62, 0.30), swing >= 45 ? FigColors.warn : c.sub,
        size: 10, mono: true);
    label(canvas, 'off the arrow ${toArrow.round()}° (needs ≤ 45°)', s.p(0.62, 0.40),
        toArrow <= 45 ? FigColors.warn : c.sub, size: 10, mono: true);
    if (flagged) {
      tag(canvas, 'ILLEGAL TURN', s.p(0.62, 0.52), FigColors.fail, Colors.white, size: 11);
    }
  }
}

/// A stop line drawn in the light's colour; only crossing on red counts.
class CrossLinePainter extends FigurePainter {
  CrossLinePainter(super.t, super.dark);

  static String _light(double x) {
    final f = x % 1.0;
    if (f < 0.5) return 'red';
    if (f < 0.8) return 'green';
    return 'yellow';
  }

  static const double _clearS = 0.5565; // progress where the ground point is clearly past the line

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    canvas.drawRect(Rect.fromLTRB(s.p(0.12, 0).dx, s.r.top, s.p(0.64, 0).dx, s.r.bottom), fill(c.road));
    final lit = _light(t);
    final lineColour = switch (lit) {
      'red' => FigColors.fail,
      'green' => FigColors.pass,
      _ => FigColors.warn,
    };
    canvas.drawLine(s.p(0.12, 0.5), s.p(0.64, 0.5), stroke(lineColour, 4));
    label(canvas, 'stop line', s.p(0.66, 0.5), c.mute, size: 9.5);
    trafficLight(canvas, s.p(0.80, 0.10), s.h(0.52), lit, c);
    label(canvas, 'light: $lit', s.p(0.82, 0.78), lineColour, size: 10, mono: true);

    for (final (laneX, off, name) in [(0.26, 0.2065, '#3'), (0.48, 0.9065, '#8')]) {
      final p = (t + off) % 1.0;
      final g = lerp(1.1, -0.05, p); // ground point, as a fraction of the height
      final r = Rect.fromLTRB(
        s.p(laneX - 0.03, 0).dx,
        s.p(0, g).dy - s.h(0.2),
        s.p(laneX + 0.03, 0).dx,
        s.p(0, g).dy,
      );
      carTop(canvas, r, c);
      canvas.drawCircle(Offset(r.center.dx, r.bottom), 2.6, fill(FigColors.warn));
      final crossed = p > _clearS;
      final crossTime = ((_clearS - off) % 1.0 + 1.0) % 1.0;
      final wasRed = _light(crossTime) == 'red';
      if (!crossed) {
        detectionBox(canvas, r.inflate(2), FigColors.blue, text: name);
      } else if (wasRed) {
        detectionBox(canvas, r.inflate(2), FigColors.fail, text: 'RED LIGHT $name');
      } else {
        detectionBox(canvas, r.inflate(2), FigColors.pass, text: 'crossed on green', textColor: Colors.black);
      }
    }
    label(canvas, 'orange dot = ground point; it must be clearly past the line',
        s.p(0.03, 0.96), c.mute, size: 9);
  }
}

/// The track’s settled class meets the zone’s list.
class VehicleTypePainter extends FigurePainter {
  VehicleTypePainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final laneY = 0.56;
    canvas.drawRect(Rect.fromLTRB(s.r.left, s.p(0, 0.40).dy, s.r.right, s.p(0, 0.74).dy), fill(c.road));
    final zone = Rect.fromLTRB(s.p(0.30, 0).dx, s.p(0, 0.38).dy, s.p(0.74, 0).dx, s.p(0, 0.76).dy);
    canvas.drawRect(zone, fill(FigColors.blue.withValues(alpha: 0.10)));
    dashedRect(canvas, zone, FigColors.blue, width: 1.4);
    label(canvas, 'bus lane · allowed: bus', Offset(zone.left, zone.top - 8), FigColors.blue, size: 9.5);
    label(canvas, 'type = most common class over the whole track', s.p(0.03, 0.08), c.mute, size: 9.5);

    for (final (name, from, to, wide) in [('bus', 0.0, 0.5, 0.17), ('car', 0.5, 1.0, 0.10)]) {
      final p = seg(t, from, to);
      if (p <= 0 || p >= 1) continue;
      final x = lerp(-0.1, 1.1, p);
      final r = Rect.fromCenter(center: s.p(x, laneY), width: s.w(wide), height: s.h(0.17));
      carH(canvas, r, c);
      final inZone = zone.contains(Offset(r.center.dx, r.bottom));
      final unknown = p < 0.12;
      final shownType = unknown ? 'unknown' : name;
      final inside = inZone ? (r.center.dx - zone.left) / zone.width * 2.0 : 0.0; // seconds inside
      final banned = name == 'car' && !unknown;
      final flagged = banned && inside >= 1.0;
      final colour = flagged ? FigColors.fail : (name == 'bus' && inZone ? FigColors.pass : FigColors.blue);
      final text = flagged
          ? 'RESTRICTED LANE'
          : (unknown ? 'unknown: not judged yet' : '$shownType${inZone && banned ? ' · inside ${inside.toStringAsFixed(1)} s' : ''}');
      detectionBox(canvas, r.inflate(2), colour, text: text, textColor: Colors.white);
    }
  }
}

/// Smoothed path, lateral offset from the straight line, reversals counted.
class WeavingPainter extends FigurePainter {
  WeavingPainter(super.t, super.dark);

  static double _x(double u) => 0.26 + 0.085 * seg(u, 0.0, 0.3) * math.sin(u * 3 * 2 * math.pi);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    canvas.drawRect(Rect.fromLTRB(s.p(0.08, 0).dx, s.r.top, s.p(0.46, 0).dx, s.r.bottom), fill(c.road));
    final u = ease(seg(t, 0.05, 0.92));
    Offset pt(double q) => s.p(_x(q), 1.0 - q * 0.82);

    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i <= 80; i++) {
      final q = i / 80 * u;
      path.lineTo(pt(q).dx, pt(q).dy);
    }
    canvas.drawPath(path, stroke(FigColors.blue, 1.8));
    dashedPath(canvas, Path()..moveTo(pt(0).dx, pt(0).dy)..lineTo(pt(u).dx, pt(u).dy), stroke(c.mute, 1.1));

    // lateral offsets from the line first → last
    final a = pt(0);
    final b = pt(u);
    final dir = b - a;
    final len = dir.distance;
    final lats = <double>[];
    if (len > 1) {
      for (var i = 0; i <= 60; i++) {
        final p = pt(i / 60 * u) - a;
        lats.add((p.dx * (-dir.dy / len) + p.dy * (dir.dx / len)) / s.r.width);
      }
    }
    const carW = 0.065;
    final swings = lats.isEmpty ? 0 : countSwings(lats, 0.5 * carW);
    final flagged = swings >= 2;

    final car = Rect.fromCenter(center: pt(u) - Offset(0, s.h(0.09)), width: s.w(carW), height: s.h(0.18));
    carTop(canvas, car, c);
    detectionBox(canvas, car.inflate(2), flagged ? FigColors.fail : FigColors.blue,
        text: flagged ? 'SWERVING' : '#5');

    // chart
    final plot = Rect.fromLTWH(s.p(0.55, 0).dx, s.p(0, 0.16).dy, s.w(0.40), s.h(0.58));
    canvas.drawRect(plot, fill(c.surface));
    canvas.drawRect(plot, stroke(c.line));
    final mid = plot.center.dy;
    canvas.drawLine(Offset(plot.left, mid), Offset(plot.right, mid), stroke(c.mute, 1));
    final amp = 0.5 * carW * s.r.width * 1.0;
    for (final sign in [-1, 1]) {
      dashedPath(canvas, Path()..moveTo(plot.left, mid + sign * amp)..lineTo(plot.right, mid + sign * amp),
          stroke(FigColors.warn, 1));
    }
    if (lats.length > 1) {
      final cp = Path();
      for (var i = 0; i < lats.length; i++) {
        final x = plot.left + plot.width * i / 60;
        final y = mid + lats[i] * s.r.width * 1.0;
        if (i == 0) {
          cp.moveTo(x, y);
        } else {
          cp.lineTo(x, y.clamp(plot.top, plot.bottom));
        }
      }
      canvas.drawPath(cp, stroke(FigColors.blue, 1.6));
    }
    label(canvas, 'sideways offset', Offset(plot.left, plot.top - 9), c.mute, size: 9.5);
    label(canvas, '± ½ box width', Offset(plot.right, plot.top - 9), FigColors.warn,
        size: 9, align: TextAlign.right, mono: true);
    label(canvas, 'reversals: $swings (needs 2)', Offset(plot.left, plot.bottom + 16),
        flagged ? FigColors.fail : c.sub, size: 10, mono: true);
  }
}

/// Amber on a vehicle’s edge must switch on and off in a steady rhythm.
class SignalPainter extends FigurePainter {
  SignalPainter(super.t, super.dark);

  static double _sample(bool blinks, double time) {
    if (!blinks) return 0.02 + 0.002 * math.sin(time * 9);
    return (time * 1.25) % 1.0 < 0.5 ? 0.30 : 0.04; // 1.25 Hz
  }

  void _panel(Canvas canvas, Scene s, double x0, bool blinks) {
    final w = s.w(0.46);
    final car = Rect.fromLTWH(s.p(x0, 0).dx + w * 0.36, s.p(0, 0.10).dy, w * 0.28, s.h(0.34));
    final now = t * 5;
    final on = _sample(blinks, now) > 0.15;
    carTop(canvas, car, c);
    if (on) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(car.left - 3, car.top + 2, 5, car.height * 0.2), const Radius.circular(2)),
        fill(const Color(0xFFFFB020)),
      );
    }
    dashedRect(canvas, Rect.fromLTWH(car.left, car.top, car.width * 0.3, car.height), FigColors.warn, width: 1);
    label(canvas, blinks ? 'driver signals' : 'driver does not', Offset(car.center.dx, car.bottom + 11), c.sub,
        size: 9.5, align: TextAlign.center);

    final plot = Rect.fromLTWH(s.p(x0, 0).dx + w * 0.04, s.p(0, 0.60).dy, w * 0.92, s.h(0.26));
    canvas.drawRect(plot, fill(c.surface));
    canvas.drawRect(plot, stroke(c.line));
    final samples = <(double, double)>[];
    final path = Path();
    for (var i = 0; i <= 50; i++) {
      final time = i / 10.0;
      if (time > now) break;
      final v = _sample(blinks, time);
      samples.add((time, v));
      final p = Offset(plot.left + plot.width * time / 5, plot.bottom - plot.height * v / 0.34);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, stroke(const Color(0xFFFFB020), 1.5));
    label(canvas, 'amber on the left edge, last 5 s', Offset(plot.left, plot.top - 9), c.mute, size: 9);
    final blinking = isBlinking(samples);
    final done = t > 0.9;
    final text = blinking
        ? 'steady blinking: fine'
        : (done ? 'no blinking: FLAGGED' : 'watching…');
    label(canvas, text, Offset(plot.left, plot.bottom + 14),
        blinking ? FigColors.pass : (done ? FigColors.fail : c.mute),
        size: 10, mono: true, weight: FontWeight.w600);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    _panel(canvas, s, 0.02, true);
    canvas.drawLine(s.p(0.5, 0.08), s.p(0.5, 0.92), stroke(c.line));
    _panel(canvas, s, 0.52, false);
  }
}

// Frame checks ───────────────────────────────────────────────────────────────

class RidersPainter extends FigurePainter {
  RidersPainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    canvas.drawRect(Rect.fromLTRB(s.r.left, s.p(0, 0.86).dy, s.r.right, s.r.bottom), fill(c.road));
    final big = s.h(0.78);
    final cx = s.p(0.34, 0).dx;
    final ground = s.p(0, 0.86).dy;
    moto(canvas, Offset(cx, ground), big, c);
    final zoneL = cx - 0.42 * big;
    final zoneR = cx + 0.42 * big;
    final riderTop = ground - 1.0 * big;
    dashedRect(canvas, Rect.fromLTRB(zoneL, riderTop, zoneR, ground), FigColors.blue, width: 1.1);
    label(canvas, 'rider zone: feet inside the bike’s width', Offset(zoneL, riderTop - 8), FigColors.blue, size: 9);

    final h = 0.5 * big;
    final seatY = ground - 0.42 * big;
    final walk = ease(seg(t, 0.30, 0.55));
    final thirdX = lerp(s.p(0.92, 0).dx, cx - 0.30 * big, walk);
    final thirdFeetY = lerp(ground, seatY, walk);
    final people = [
      (Offset(cx + 0.14 * big, seatY), 'rider 1'),
      (Offset(cx - 0.10 * big, seatY), 'rider 2'),
      (Offset(thirdX, thirdFeetY), walk >= 1 ? 'rider 3' : 'pedestrian'),
    ];
    var count = 0;
    for (final (feet, name) in people) {
      final counts = feet.dx >= zoneL && feet.dx <= zoneR;
      if (counts) count++;
      person(canvas, feet, h, counts ? FigColors.blue : c.mute);
      label(canvas, counts ? name : '$name: not counted', Offset(feet.dx, feet.dy - h - 8),
          counts ? FigColors.blue : c.mute, size: 9, align: TextAlign.center);
    }
    final bad = count > 2;
    final x = s.p(0.64, 0).dx;
    label(canvas, 'riders counted', Offset(x, s.p(0, 0.22).dy), c.mute, size: 10);
    label(canvas, '$count', Offset(x, s.p(0, 0.38).dy), bad ? FigColors.fail : c.text,
        size: 26, weight: FontWeight.w600, mono: true);
    label(canvas, 'allowed: 2', Offset(x, s.p(0, 0.52).dy), c.sub, size: 10, mono: true);
    if (bad) tag(canvas, 'bad look', Offset(x, s.p(0, 0.62).dy), FigColors.fail, Colors.white, size: 11);
  }
}

/// A person on a vehicle: in the right place AND moving with it.
class OnboardPainter extends FigurePainter {
  OnboardPainter(super.t, super.dark);

  void _tests(Canvas canvas, Offset at, bool place, bool moves, String verdict, bool good) {
    label(canvas, 'place ${place ? '✓' : '✗'}   moves with it ${moves ? '✓' : '✗'}', at, c.sub, size: 9, mono: true);
    label(canvas, verdict, at + const Offset(0, 13), good ? FigColors.fail : c.mute, size: 9.5,
        weight: good ? FontWeight.w600 : FontWeight.w500);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final shift = lerp(0.0, 0.34, t);

    // Row 1: pickup truck, moving right. The bed is the trailing 40%.
    final g1 = s.p(0, 0.44).dy;
    canvas.drawLine(Offset(s.r.left, g1), Offset(s.r.right, g1), stroke(c.line));
    final tx = s.p(0.10 + shift, 0).dx;
    final len = s.w(0.36);
    final body = Rect.fromLTWH(tx, g1 - s.h(0.17), len, s.h(0.12));
    final cab = Rect.fromLTWH(tx + len * 0.6, g1 - s.h(0.28), len * 0.4, s.h(0.23));
    canvas.drawRect(body, fill(c.body));
    canvas.drawRect(cab, fill(c.body));
    canvas.drawRect(body, stroke(c.sub, 1));
    canvas.drawRect(cab, stroke(c.sub, 1));
    for (final fx in [0.14, 0.78]) {
      canvas.drawCircle(Offset(tx + len * fx, g1 - 2), s.h(0.035), fill(c.mute));
    }
    final bed = Rect.fromLTWH(tx, body.top - s.h(0.17), len * 0.4, s.h(0.17) + body.height);
    dashedRect(canvas, bed, FigColors.blue, width: 1.2);
    label(canvas, 'bed: rear 40%', Offset(bed.left, bed.top - 8), FigColors.blue, size: 9);
    person(canvas, Offset(tx + len * 0.2, body.top), s.h(0.2), FigColors.blue);
    _tests(canvas, Offset(s.p(0.03, 0).dx, s.p(0, 0.06).dy), true, true, 'in the bed: counted', true);
    person(canvas, Offset(s.p(0.62, 0).dx, g1), s.h(0.22), c.mute);
    _tests(canvas, Offset(s.p(0.55, 0).dx, s.p(0, 0.55).dy), true, false, 'stands still: not counted', false);

    // Row 2: bus, roof band.
    final g2 = s.p(0, 0.93).dy;
    canvas.drawLine(Offset(s.r.left, g2), Offset(s.r.right, g2), stroke(c.line));
    final bx = s.p(0.06 + shift * 0.8, 0).dx;
    final bl = s.w(0.30);
    final bus = Rect.fromLTWH(bx, g2 - s.h(0.20), bl, s.h(0.18));
    canvas.drawRect(bus, fill(c.body));
    canvas.drawRect(bus, stroke(c.sub, 1));
    final roof = Rect.fromLTWH(bus.left, bus.top - s.h(0.03), bl, bus.height * 0.3 + s.h(0.03));
    dashedRect(canvas, roof, FigColors.blue, width: 1.2);
    person(canvas, Offset(bx + bl * 0.4, bus.top), s.h(0.16), FigColors.blue);
    label(canvas, 'roof: top 30%', Offset(bus.right + 8, roof.center.dy), FigColors.blue, size: 9);
    label(canvas, 'on the roof, moving with it: counted', Offset(bus.right + 8, roof.center.dy + 14), FigColors.fail,
        size: 9, weight: FontWeight.w600);
  }
}

// Specialist checks ──────────────────────────────────────────────────────────

/// Bike box cuts the heads off; the crop covers bike and riders together.
class HelmetPainter extends FigurePainter {
  HelmetPainter(super.t, super.dark);

  void _scene(Canvas canvas, Rect area, {required bool boxes, required double union, required double conf}) {
    final big = math.min(area.width * 0.72, area.height * 0.62);
    final cx = area.center.dx;
    final ground = area.bottom - area.height * 0.10;
    moto(canvas, Offset(cx, ground), big, c);
    final h = 0.55 * big;
    final seatY = ground - 0.42 * big;
    final r1 = Offset(cx + 0.10 * big, seatY);
    final r2 = Offset(cx - 0.14 * big, seatY);
    person(canvas, r1, h, c.sub, helmet: FigColors.pass);
    person(canvas, r2, h, c.sub);
    final bike = Rect.fromLTRB(cx - 0.52 * big, ground - 0.55 * big, cx + 0.52 * big, ground);
    final all = Rect.fromLTRB(bike.left, ground - 1.0 * big, bike.right, ground);
    final box = Rect.lerp(bike, all, union)!;
    if (boxes) {
      detectionBox(canvas, box, FigColors.blue, dashed: union < 0.05, text: union < 0.05 ? 'motorcycle' : 'bike + riders');
    }
    if (conf > 0) {
      final head1 = Rect.fromCenter(center: Offset(r1.dx, r1.dy - h * 0.55), width: h * 0.42, height: h * 0.92);
      final head2 = Rect.fromCenter(center: Offset(r2.dx, r2.dy - h * 0.55), width: h * 0.42, height: h * 0.92);
      detectionBox(canvas, head1, FigColors.pass, text: 'helmet 0.91');
      detectionBox(canvas, head2, FigColors.fail, text: 'NO HELMET 0.84');
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final frame = Rect.fromLTWH(s.r.left + 0.03 * s.r.width, s.r.top + 0.08 * s.r.height, 0.50 * s.r.width,
        0.84 * s.r.height);
    canvas.drawRect(frame, fill(c.road));
    canvas.drawRect(frame, stroke(c.line));
    final union = ease(seg(t, 0.25, 0.45));
    _scene(canvas, frame, boxes: true, union: union, conf: 0);
    label(canvas, union < 0.05 ? 'the bike box alone cuts off the heads' : 'crop = bike and riders together',
        Offset(frame.left + 6, frame.top + 10), union < 0.05 ? FigColors.warn : FigColors.blue, size: 9.5);

    final side = 0.80 * s.r.height;
    final inset = Rect.fromLTWH(s.r.left + 0.62 * s.r.width, s.r.top + 0.10 * s.r.height, side, side);
    final show = seg(t, 0.5, 0.62);
    arrow(canvas, Offset(frame.right + 6, frame.center.dy), Offset(inset.left - 8, frame.center.dy),
        c.sub.withValues(alpha: show));
    canvas.drawRect(inset, fill(const Color(0xFF727272).withValues(alpha: 0.35 * show)));
    canvas.drawRect(inset, stroke(c.sub.withValues(alpha: show)));
    if (show > 0) {
      _scene(canvas, inset.deflate(8), boxes: false, union: 1, conf: seg(t, 0.7, 0.8));
      label(canvas, '320 × 320', Offset(inset.left, inset.bottom + 12), c.mute, size: 9.5, mono: true);
      if (t > 0.82) {
        tag(canvas, 'bad look', Offset(inset.right + 8, inset.top), FigColors.fail, Colors.white, size: 11);
      }
    }
  }
}

/// The cabin specialist’s safety gate, then the look. Variant 0 seatbelt, 1 phone.
class CabinPainter extends FigurePainter {
  CabinPainter(super.t, super.dark, {required this.phoneVariant});
  final bool phoneVariant;

  @override
  List<Object?> get inputs => [phoneVariant];

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final scenario = (t * 3).floor().clamp(0, 2); // 0 tinted, 1 good, 2 bad
    final car = Rect.fromLTWH(s.r.left + 0.05 * s.r.width, s.r.top + 0.14 * s.r.height, 0.36 * s.r.width,
        0.64 * s.r.height);
    carFront(canvas, car, c, tinted: scenario == 0);
    final glass = Rect.fromLTWH(car.left + car.width * 0.14, car.top + car.height * 0.1, car.width * 0.72,
        car.height * 0.4);
    if (scenario > 0) {
      // driver silhouette
      final head = Offset(glass.left + glass.width * 0.7, glass.top + glass.height * 0.34);
      canvas.drawCircle(head, glass.height * 0.17, stroke(c.sub, 1.4));
      final shoulder = Rect.fromCenter(
          center: Offset(head.dx, glass.bottom - glass.height * 0.12), width: glass.width * 0.28, height: glass.height * 0.4);
      canvas.drawArc(shoulder, math.pi, math.pi, false, stroke(c.sub, 1.4));
      if (!phoneVariant && scenario == 1) {
        canvas.drawLine(Offset(head.dx - glass.width * 0.1, glass.top + glass.height * 0.55),
            Offset(head.dx + glass.width * 0.1, glass.bottom - glass.height * 0.02), stroke(FigColors.pass, 2.2));
      }
      if (phoneVariant && scenario == 2) {
        canvas.drawRect(Rect.fromCenter(center: head + Offset(glass.height * 0.26, 0), width: 6, height: 11),
            fill(FigColors.fail));
      }
    }
    final glassName = scenario == 0 ? 'tinted_window 0.93' : 'clear_window 0.90';
    detectionBox(canvas, glass, scenario == 0 ? FigColors.warn : FigColors.blue, text: glassName, dashed: true);
    if (scenario == 1 && !phoneVariant) {
      label(canvas, 'seatbelt 0.84', Offset(glass.right - 4, glass.bottom + 12), FigColors.pass,
          size: 9, align: TextAlign.right, mono: true);
    }
    if (scenario == 2) {
      label(canvas, phoneVariant ? 'driver_phone 0.77' : 'no seatbelt seen',
          Offset(glass.right - 4, glass.bottom + 12), FigColors.fail,
          size: 9, align: TextAlign.right, mono: true);
    }

    // The gate.
    final x = s.p(0.50, 0).dx;
    final w = s.w(0.46);
    final rows = [
      ('tinted window seen?', scenario == 0 ? 'yes → skip' : 'no'),
      ('clear window seen?', scenario == 0 ? '—' : 'yes'),
      ('judge the look', switch (scenario) {
            0 => 'no look cast',
            1 => phoneVariant ? 'no phone: good look' : 'seatbelt: good look',
            _ => phoneVariant ? 'phone: bad look' : 'no belt: bad look',
          }),
    ];
    for (var i = 0; i < rows.length; i++) {
      final r = Rect.fromLTWH(x, s.p(0, 0.14 + i * 0.27).dy, w, s.h(0.20));
      final active = !(scenario == 0 && i == 2);
      final last = i == 2;
      final col = last
          ? (scenario == 0 ? c.mute : (scenario == 1 ? FigColors.pass : FigColors.fail))
          : (scenario == 0 && i == 0 ? FigColors.warn : c.sub);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
          fill(last && active ? col.withValues(alpha: 0.15) : c.surface));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), stroke(last ? col : c.line, 1.2));
      label(canvas, rows[i].$1, Offset(r.left + 8, r.center.dy), c.text, size: 9.5, maxWidth: w * 0.5);
      label(canvas, rows[i].$2, Offset(r.right - 8, r.center.dy), col,
          size: 9.5, align: TextAlign.right, mono: true, maxWidth: w * 0.46, weight: FontWeight.w600);
      if (i < 2) {
        arrow(canvas, Offset(r.center.dx, r.bottom + 2), Offset(r.center.dx, r.bottom + s.h(0.07) - 2),
            c.mute, width: 1.2, head: 4);
      }
    }
  }
}

/// A motorcycle’s mirrors are only counted from the front or rear.
class MirrorPainter extends FigurePainter {
  MirrorPainter(super.t, super.dark);

  void _front(Canvas canvas, Offset centre, double size, int mirrors) {
    final bar = stroke(c.sub, 2);
    canvas.drawLine(centre + Offset(-size * 0.5, 0), centre + Offset(size * 0.5, 0), bar);
    canvas.drawLine(centre, centre + Offset(0, size * 0.85), stroke(c.sub, 3));
    canvas.drawCircle(centre + Offset(0, size * 0.18), size * 0.16, stroke(c.sub, 1.4));
    for (var i = 0; i < 2; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      final base = centre + Offset(side * size * 0.5, 0);
      final present = i < mirrors;
      canvas.drawLine(base, base + Offset(side * size * 0.04, -size * 0.3),
          stroke(present ? c.sub : c.line, 1.4));
      if (present) {
        canvas.drawOval(Rect.fromCenter(center: base + Offset(side * size * 0.05, -size * 0.36), width: size * 0.2, height: size * 0.14),
            fill(FigColors.pass.withValues(alpha: 0.6)));
      } else {
        dashedRect(canvas, Rect.fromCenter(center: base + Offset(side * size * 0.05, -size * 0.36), width: size * 0.2, height: size * 0.14),
            FigColors.fail, width: 1);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final scenario = (t * 3).floor().clamp(0, 2); // 0 side, 1 front good, 2 front bad
    final centre = s.p(0.26, 0.60);
    final unit = s.h(0.7);
    if (scenario == 0) {
      moto(canvas, s.p(0.26, 0.84), unit * 1.1, c);
      arrow(canvas, s.p(0.10, 0.14), s.p(0.26, 0.14), c.sub, width: 1.6);
      label(canvas, 'travels sideways', s.p(0.28, 0.14), c.mute, size: 9.5);
    } else {
      _front(canvas, centre, unit * 0.62, scenario == 1 ? 2 : 1);
      arrow(canvas, s.p(0.40, 0.30), s.p(0.40, 0.10), c.sub, width: 1.6);
      label(canvas, 'travels up the picture', s.p(0.42, 0.20), c.mute, size: 9.5);
    }
    final x = s.p(0.54, 0).dx;
    final w = s.w(0.42);
    final rows = [
      ('front or rear view?', scenario == 0 ? 'no → skip' : 'yes'),
      ('mirrors seen', scenario == 0 ? '—' : (scenario == 1 ? '2 of 2' : '1 of 2')),
      ('look', switch (scenario) { 0 => 'not counted', 1 => 'good look', _ => 'bad look' }),
    ];
    for (var i = 0; i < rows.length; i++) {
      final r = Rect.fromLTWH(x, s.p(0, 0.14 + i * 0.27).dy, w, s.h(0.20));
      final last = i == 2;
      final col = last ? (scenario == 0 ? c.mute : (scenario == 1 ? FigColors.pass : FigColors.fail)) : c.sub;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
          fill(last && scenario > 0 ? col.withValues(alpha: 0.15) : c.surface));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), stroke(last ? col : c.line, 1.2));
      label(canvas, rows[i].$1, Offset(r.left + 8, r.center.dy), c.text, size: 9.5, maxWidth: w * 0.55);
      label(canvas, rows[i].$2, Offset(r.right - 8, r.center.dy), col,
          size: 9.5, align: TextAlign.right, mono: true, maxWidth: w * 0.4, weight: FontWeight.w600);
    }
  }
}

/// Six fair looks with no plate make a suspicion; a plate at any time clears it.
class PlatePainter extends FigurePainter {
  PlatePainter(super.t, super.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final s = begin(canvas, size);
    final scenarioB = t >= 0.5;
    final l = (scenarioB ? t - 0.5 : t) / 0.5;

    // approaching vehicle
    final px = lerp(40, 150, l);
    final width = s.w(0.07) + s.w(0.12) * l;
    final car = Rect.fromCenter(center: s.p(0.18, 0.50), width: width, height: width * 0.7);
    // look k happens at 0.06 + 0.11k; looks 0,1 are too small to count
    const looks = 8;
    var fairNoPlate = 0;
    var cleared = false;
    final pips = <(Color, String)>[];
    for (var k = 0; k < looks; k++) {
      final at = 0.06 + 0.11 * k;
      if (l < at) {
        pips.add((c.line, ''));
        continue;
      }
      if (k < 2) {
        pips.add((c.mute, '–'));
      } else if (scenarioB && k == 5) {
        cleared = true;
        pips.add((FigColors.pass, '✓'));
      } else if (cleared) {
        pips.add((c.line, ''));
      } else {
        fairNoPlate++;
        pips.add((FigColors.warn, '✕'));
      }
    }
    final plateVisible = scenarioB && l >= 0.06 + 0.11 * 5;
    carFront(canvas, car, c, plate: plateVisible);
    dashedRect(canvas, car.inflate(3), FigColors.blue, width: 1.2);
    label(canvas, 'search the whole vehicle', Offset(car.left - 4, car.top - 12), FigColors.blue, size: 9);
    if (plateVisible) {
      detectionBox(canvas, Rect.fromCenter(center: Offset(car.center.dx, car.top + car.height * 0.84),
          width: car.width * 0.34, height: car.height * 0.17), FigColors.pass, text: 'plate 0.62');
    }
    label(canvas, 'box ${px.round()} px wide ${px < 60 ? '(too small)' : ''}', Offset(car.left, car.bottom + 14),
        px < 60 ? FigColors.warn : c.sub, size: 9.5, mono: true);

    // pips
    final x0 = s.p(0.45, 0).dx;
    final cw = s.w(0.062);
    label(canvas, scenarioB ? 'vehicle B' : 'vehicle A', Offset(x0, s.p(0, 0.12).dy), c.sub, size: 10);
    label(canvas, 'looks over time', Offset(x0, s.p(0, 0.26).dy), c.mute, size: 9.5);
    for (var k = 0; k < looks; k++) {
      final r = Rect.fromLTWH(x0 + k * (cw + 4), s.p(0, 0.34).dy, cw, s.h(0.16));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          fill(pips[k].$1.withValues(alpha: pips[k].$2.isEmpty ? 1 : 0.22)));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
          stroke(pips[k].$2.isEmpty ? c.line : pips[k].$1, 1));
      label(canvas, pips[k].$2, r.center, pips[k].$1, size: 11, align: TextAlign.center, weight: FontWeight.w600);
    }
    label(canvas, '– too small to count    ✕ fair look, no plate    ✓ plate found', Offset(x0, s.p(0, 0.58).dy),
        c.mute, size: 8.5);
    label(canvas, 'fair looks without a plate: $fairNoPlate of 6', Offset(x0, s.p(0, 0.72).dy),
        c.sub, size: 10, mono: true);
    final pending = !cleared && fairNoPlate >= 6;
    if (pending) {
      tag(canvas, 'NO PLATE SEEN YET (pending)', Offset(x0, s.p(0, 0.82).dy), FigColors.warn, Colors.black, size: 10.5);
    } else if (cleared) {
      tag(canvas, 'plate found: suspicion cleared', Offset(x0, s.p(0, 0.82).dy), FigColors.pass, Colors.black, size: 10.5);
    }
  }
}
