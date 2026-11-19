import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The "Processing" view while the backend fills its playback buffer. It only shows that something is being processed: a dimmed
/// picture (the newest one that is finished, when there is one), a scan line that sweeps over it, corner brackets on the vehicles that
/// were found (they light up as the line passes), and the word "Processing". No numbers and no claims.
///
/// With [overPicture] it is laid over the picture that is already on screen (the buffer ran dry): just the sweep and the word.
class ProcessingScan extends StatefulWidget {
  const ProcessingScan({super.key, this.picture, this.pictureWidth, this.pictureHeight, this.boxes = const [], this.overPicture = false});

  final Uint8List? picture;
  final double? pictureWidth;
  final double? pictureHeight;

  /// Boxes (x, y, width, height) in the pixels of the picture.
  final List<Rect> boxes;
  final bool overPicture;

  @override
  State<ProcessingScan> createState() => _ProcessingScanState();
}

class _ProcessingScanState extends State<ProcessingScan> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.pictureWidth, h = widget.pictureHeight;
    final ratio = (w != null && h != null && h > 0) ? w / h : 16 / 9;
    final over = widget.overPicture;
    final stack = Stack(fit: StackFit.expand, children: [
      if (!over) const ColoredBox(color: Colors.black),
      if (!over && widget.picture != null) Image.memory(widget.picture!, fit: BoxFit.fill, gaplessPlayback: true),
      ColoredBox(color: Colors.black.withValues(alpha: over ? 0.35 : 0.55)),
      AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          size: Size.infinite,
          painter: _ScanPainter(_c.value, over ? const [] : widget.boxes, w ?? 1280, h ?? 720),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('PROCESSING', style: TextStyle(color: Colors.cyanAccent, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 4)),
            const SizedBox(height: 8),
            SizedBox(
              width: 190,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(minHeight: 3, color: Colors.cyanAccent, backgroundColor: Colors.cyanAccent.withValues(alpha: 0.15)),
              ),
            ),
          ]),
        ),
      ),
    ]);
    return Center(child: AspectRatio(aspectRatio: ratio, child: ClipRect(child: stack)));
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter(this.t, this.boxes, this.srcW, this.srcH);

  final double t;               // 0..1, repeats
  final List<Rect> boxes;
  final double srcW;
  final double srcH;

  @override
  void paint(Canvas canvas, Size size) {
    const cyan = Colors.cyanAccent;
    // a faint grid
    final grid = Paint()..color = cyan.withValues(alpha: 0.07)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 56) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 56) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // brackets on the vehicles that were found: they light up as the scan line passes and fade out again as it wraps
    final sweepX = Curves.easeInOut.transform(t) * size.width;
    final sx = size.width / srcW, sy = size.height / srcH;
    for (final b in boxes) {
      final r = Rect.fromLTWH(b.left * sx, b.top * sy, b.width * sx, b.height * sy);
      final alpha = ((sweepX - r.center.dx) / 70).clamp(0.0, 1.0) * (t > 0.92 ? (1 - t) / 0.08 : 1.0);
      if (alpha <= 0) continue;
      final len = (r.shortestSide * 0.28).clamp(8.0, 24.0);
      final p = Paint()..color = cyan.withValues(alpha: alpha)..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.square;
      final path = Path()
        ..moveTo(r.left, r.top + len)..lineTo(r.left, r.top)..lineTo(r.left + len, r.top)
        ..moveTo(r.right - len, r.top)..lineTo(r.right, r.top)..lineTo(r.right, r.top + len)
        ..moveTo(r.right, r.bottom - len)..lineTo(r.right, r.bottom)..lineTo(r.right - len, r.bottom)
        ..moveTo(r.left + len, r.bottom)..lineTo(r.left, r.bottom)..lineTo(r.left, r.bottom - len);
      canvas.drawPath(path, p);
    }

    // the scan line with its trail
    final trailW = size.width * 0.18;
    canvas.drawRect(
      Rect.fromLTRB(sweepX - trailW, 0, sweepX, size.height),
      Paint()..shader = LinearGradient(colors: [cyan.withValues(alpha: 0), cyan.withValues(alpha: 0.26)]).createShader(Rect.fromLTRB(sweepX - trailW, 0, sweepX, size.height)),
    );
    canvas.drawLine(Offset(sweepX, 0), Offset(sweepX, size.height), Paint()..color = cyan.withValues(alpha: 0.55)..strokeWidth = 6..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawLine(Offset(sweepX, 0), Offset(sweepX, size.height), Paint()..color = Colors.white..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(covariant _ScanPainter old) => old.t != t || old.boxes != boxes;
}
