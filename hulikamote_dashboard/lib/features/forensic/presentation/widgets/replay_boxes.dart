import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The boxes of a replay video, one list per video frame (boxes.json, written next to evidence_replay.mp4 by the backend).
/// They are drawn over the video here, not burned into it, so their lines stay thin when the video is zoomed.
class ReplayBoxes {
  const ReplayBoxes({required this.width, required this.height, required this.fps, required this.frames});

  final int width, height; // the video's own pixels (the boxes use them)
  final double fps;
  final List<List<BoxSpec>> frames;

  static ReplayBoxes? fromJson(Object? json) {
    if (json is! Map) return null;
    final w = (json['w'] as num?)?.toInt() ?? 0, h = (json['h'] as num?)?.toInt() ?? 0;
    final fps = (json['fps'] as num?)?.toDouble() ?? 0;
    if (w <= 0 || h <= 0 || fps <= 0) return null;
    return ReplayBoxes(
      width: w,
      height: h,
      fps: fps,
      frames: [
        for (final f in (json['frames'] as List? ?? const []))
          [for (final b in (f as List)) if (b is Map) BoxSpec.fromJson(Map<String, dynamic>.from(b))],
      ],
    );
  }

  /// The boxes to show at [seconds] into the video (none past the end).
  List<BoxSpec> at(double seconds) {
    final i = (seconds * fps).floor();
    return i < 0 || i >= frames.length ? const [] : frames[i];
  }
}

/// One thing to draw: a vehicle box with its label lines, a mark box (why it was flagged), or a note under a vehicle.
class BoxSpec {
  const BoxSpec({this.box, required this.color, this.lines = const [], this.plate, this.note, this.noteAt, this.timer});

  final List<double>? box; // x, y, w, h in video pixels
  final Color color;
  final List<String> lines;
  final List<double>? plate;
  final String? note;
  final List<double>? noteAt;
  final String? timer; // a stopwatch chip on the bottom edge of [box] (e.g. "PARKED 0:07 / 0:10"); nothing else is drawn for it

  static List<double>? _nums(Object? v) => v is List ? [for (final n in v) (n as num).toDouble()] : null;

  factory BoxSpec.fromJson(Map<String, dynamic> j) {
    final c = _nums(j['color']) ?? const [255, 0, 0];
    return BoxSpec(
      box: _nums(j['box']),
      color: Color.fromARGB(255, c[0].round(), c[1].round(), c[2].round()),
      lines: [for (final l in (j['lines'] as List? ?? const [])) '$l'],
      plate: _nums(j['plate']),
      note: j['note'] as String?,
      noteAt: _nums(j['at']),
      timer: j['timer'] as String?,
    );
  }
}

/// Paints the boxes of the current frame over a video that is fitted (contain) into the painter's area. Line widths and label
/// size are in SCREEN pixels: they are divided by the zoom, so the boxes never grow with the picture.
class ReplayBoxesPainter extends CustomPainter {
  ReplayBoxesPainter({required this.boxes, required this.seconds, required this.zoom})
    : super(repaint: Listenable.merge([seconds, zoom]));

  final ReplayBoxes boxes;
  final ValueListenable<double> seconds;
  final TransformationController zoom;

  static const lineWidth = 1.2, plateWidth = 1.0, fontSize = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = math.min(size.width / boxes.width, size.height / boxes.height);
    final z = zoom.value.getMaxScaleOnAxis();
    final px = 1 / (fit * z); // one screen pixel, in video pixels
    canvas.save();
    canvas.translate((size.width - boxes.width * fit) / 2, (size.height - boxes.height * fit) / 2);
    canvas.scale(fit);
    canvas.clipRect(Rect.fromLTWH(0, 0, boxes.width.toDouble(), boxes.height.toDouble()));
    for (final b in boxes.at(seconds.value)) {
      if (b.note != null && b.noteAt != null) {
        _note(canvas, b.note!, b.noteAt!, px);
      } else if (b.timer != null && b.box != null) {
        _timer(canvas, b, px);
      } else if (b.box != null) {
        final r = Rect.fromLTWH(b.box![0], b.box![1], b.box![2], b.box![3]);
        canvas.drawRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = lineWidth * px..color = b.color);
        _label(canvas, r, b, px);
        final p = b.plate;
        if (p != null) {
          canvas.drawRect(
            Rect.fromLTWH(p[0], p[1], p[2], p[3]),
            Paint()..style = PaintingStyle.stroke..strokeWidth = plateWidth * px..color = Colors.cyanAccent,
          );
        }
      }
    }
    canvas.restore();
  }

  /// The label lines stacked above the box (the last line, the vehicle, nearest to it), kept inside the picture: a vehicle that is
  /// half outside gets its label on the visible part, inside its top edge when there is no room above.
  void _label(Canvas canvas, Rect r, BoxSpec b, double px) {
    if (b.lines.isEmpty) return;
    final dark = b.color.computeLuminance() > 0.6;
    final rows = [
      for (final l in b.lines)
        TextPainter(
          text: TextSpan(text: l, style: TextStyle(fontSize: fontSize * px, fontWeight: FontWeight.w600, color: dark ? Colors.black : Colors.white)),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final pad = 2 * px;
    final width = rows.map((t) => t.width).reduce(math.max) + 2 * pad;
    final height = rows.fold<double>(0, (s, t) => s + t.height + pad);
    final x = r.left.clamp(0.0, math.max(0.0, boxes.width - width)).toDouble();
    var y = math.max(0.0, r.top) - height;
    if (y < 0) y = math.max(0.0, r.top);
    y = math.min(y, math.max(0.0, boxes.height - height));
    for (final t in rows) {
      canvas.drawRect(Rect.fromLTWH(x, y, t.width + 2 * pad, t.height + pad), Paint()..color = b.color);
      t.paint(canvas, Offset(x + pad, y + pad / 2));
      y += t.height + pad;
    }
  }

  /// The stopwatch: a small chip sitting on the bottom edge of the vehicle's box (the labels above the box are not touched).
  void _timer(Canvas canvas, BoxSpec b, double px) {
    final box = b.box!;
    final dark = b.color.computeLuminance() > 0.6;
    final text = TextPainter(
      text: TextSpan(text: b.timer, style: TextStyle(fontSize: fontSize * px, fontWeight: FontWeight.w700, color: dark ? Colors.black : Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = 3 * px;
    final w = text.width + 2 * pad, h = text.height + pad;
    final x = box[0].clamp(0.0, math.max(0.0, boxes.width - w)).toDouble();
    final y = (box[1] + box[3] - h).clamp(0.0, math.max(0.0, boxes.height - h)).toDouble();
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = b.color);
    text.paint(canvas, Offset(x + pad, y + pad / 2));
  }

  void _note(Canvas canvas, String text, List<double> at, double px) {
    final style = TextStyle(fontSize: fontSize * 1.2 * px, fontWeight: FontWeight.w700);
    final outline = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 3 * px..color = Colors.black)),
      textDirection: TextDirection.ltr,
    )..layout();
    final fill = TextPainter(text: TextSpan(text: text, style: style.copyWith(color: const Color(0xFFFF3B30))), textDirection: TextDirection.ltr)..layout();
    final x = at[0].clamp(0.0, math.max(0.0, boxes.width - fill.width)).toDouble();
    final y = at[1].clamp(0.0, math.max(0.0, boxes.height - fill.height)).toDouble();
    outline.paint(canvas, Offset(x, y));
    fill.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(ReplayBoxesPainter old) => old.boxes != boxes;
}
