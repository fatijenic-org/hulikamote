import 'package:flutter/material.dart';

import '../../domain/harvest_models.dart';
import 'fx.dart';

/// The tile key of the "same car?" questions (they are not a model of their own).
const harvestPairsKey = 'reid_pairs';

/// Colours and icons of the Harvest tab, in one place.
class HarvestStyle {
  HarvestStyle._();

  static Color state(HarvestState s) => switch (s) {
        HarvestState.check => Fx.warning,
        HarvestState.label => const Color(0xFFFF8A4C),
        HarvestState.ready => Fx.accent,
        HarvestState.skipped => const Color(0xFF9AA5B1),
        HarvestState.accepted => Fx.success,
      };

  static IconData stateIcon(HarvestState s) => switch (s) {
        HarvestState.check => Icons.visibility_outlined,
        HarvestState.label => Icons.add_box_outlined,
        HarvestState.ready => Icons.check_circle_outline,
        HarvestState.skipped => Icons.help_outline,
        HarvestState.accepted => Icons.library_add_check_outlined,
      };

  /// Short words used on filter chips and legends.
  static String stateShort(HarvestState s) => switch (s) {
        HarvestState.check => 'to check',
        HarvestState.label => 'to box',
        HarvestState.ready => 'ready',
        HarvestState.skipped => 'skipped',
        HarvestState.accepted => 'added',
      };

  static IconData categoryIcon(String key) => switch (key) {
        'plate_specialist' => Icons.pin_outlined,
        'helmet_specialist' => Icons.sports_motorsports_outlined,
        'cabin_specialist' => Icons.directions_car_outlined,
        'primary_anchor' => Icons.local_shipping_outlined,
        harvestPairsKey => Icons.compare_outlined,
        'plate_ocr' => Icons.text_fields,
        'reid' => Icons.join_inner,
        _ => Icons.photo_library_outlined,
      };

  static Color categoryColor(String key) => switch (key) {
        'plate_specialist' => const Color(0xFF5B9DFF),
        'helmet_specialist' => const Color(0xFFB388FF),
        'cabin_specialist' => const Color(0xFF4DD0E1),
        'primary_anchor' => const Color(0xFFFF8A65),
        harvestPairsKey => const Color(0xFF4CC38A),
        'plate_ocr' => const Color(0xFFFFB454),
        'reid' => const Color(0xFF4CC38A),
        _ => Fx.accent,
      };

  static Color boxColor(int cls) => Color(harvestBoxColors[cls % harvestBoxColors.length]);
}

/// "just now", "5 min ago", "3 h ago", or the date.
String agoText(DateTime? t, DateTime now) {
  if (t == null) return 'unknown';
  final d = now.difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// 1234 -> "1,234".
String grouped(int n) {
  final s = n.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return n < 0 ? '-$out' : '$out';
}

/// Draws YOLO boxes over a picture that is shown with `BoxFit.contain`.
class BoxesPainter extends CustomPainter {
  BoxesPainter({required this.boxes, required this.aspect, this.stroke = 2});

  final List<HarvestBox> boxes;

  /// width / height of the picture.
  final double aspect;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (boxes.isEmpty || size.isEmpty) return;
    final fitted = applyBoxFit(BoxFit.contain, Size(aspect, 1), size).destination;
    final dest = Alignment.center.inscribe(fitted, Offset.zero & size);
    for (final b in boxes) {
      final rect = Rect.fromCenter(
        center: Offset(dest.left + b.cx * dest.width, dest.top + b.cy * dest.height),
        width: b.w * dest.width,
        height: b.h * dest.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = HarvestStyle.boxColor(b.cls)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(BoxesPainter old) => old.boxes != boxes || old.aspect != aspect || old.stroke != stroke;
}

/// A picture on a dark ground with its boxes on top.
class PictureWithBoxes extends StatelessWidget {
  const PictureWithBoxes({
    super.key,
    required this.image,
    required this.aspect,
    this.boxes = const [],
    this.stroke = 2,
    this.errorLabel = '',
  });

  final ImageProvider image;
  final double aspect;
  final List<HarvestBox> boxes;
  final double stroke;
  final String errorLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      FxImage(image: image, fit: BoxFit.contain, errorLabel: errorLabel),
      if (boxes.isNotEmpty)
        CustomPaint(painter: BoxesPainter(boxes: boxes, aspect: aspect, stroke: stroke)),
    ]);
  }
}
