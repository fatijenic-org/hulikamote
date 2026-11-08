import 'forensic_models.dart';

String _unread(String? text) {
  final t = (text ?? '').trim();
  return const {'unidentified', 'no_plate_found', 'OCR_NOT_INSTALLED'}.contains(t) ? '' : t;
}

/// The answer to "Read again": the new ticket list and what the second look found.
class RereadResult {
  const RereadResult({
    required this.tickets,
    required this.checked,
    required this.found,
    this.noPicture = 0,
    this.noPlate = 0,
    this.suggested = '',
    this.keptManual = false,
  });

  final List<ForensicTicket> tickets;

  /// Photos looked at, and in how many a plate was found. The others had no clean picture, or no plate in it.
  final int checked;
  final int found;
  final int noPicture;
  final int noPlate;

  /// What the new vote reads ('' = nothing readable).
  final String suggested;

  /// The reviewer had typed a plate: it stays, [suggested] is only a suggestion.
  final bool keptManual;

  factory RereadResult.fromJson(Map<String, dynamic> json) {
    final r = Map<String, dynamic>.from(json['reread'] as Map? ?? const {});
    int n(String key) => (r[key] as num?)?.toInt() ?? 0;
    return RereadResult(
      tickets: ForensicTicket.parseList(json['tickets'] as List),
      checked: n('checked'),
      found: n('found'),
      noPicture: n('no_picture'),
      noPlate: n('no_plate'),
      suggested: _unread(r['suggested'] as String?),
      keptManual: r['kept_manual'] as bool? ?? false,
    );
  }

  /// One sentence for the reviewer.
  String get message {
    if (found == 0) {
      final why = noPicture > 0 && noPlate == 0 ? ' They have no clean picture to search.' : '';
      return 'No plate found in the $checked photo${checked == 1 ? '' : 's'}.$why Try “Draw plate”.';
    }
    if (suggested.isEmpty) return 'A plate was found in $found photo${found == 1 ? '' : 's'} but could not be read. Try “Draw plate”.';
    return keptManual ? 'The system now reads $suggested. The plate you typed was kept.' : 'Read again: $suggested.';
  }
}

/// What the OCR read inside a box the reviewer drew on a photo.
class PlateBoxRead {
  const PlateBoxRead({required this.text, this.raw = '', this.confidence = 0, this.crop});

  /// '' when the box holds nothing readable.
  final String text;
  final String raw;
  final double confidence;

  /// The saved picture of the box (under snapshots/evidence), so the right number can train the OCR.
  final String? crop;

  factory PlateBoxRead.fromJson(Map<String, dynamic> json) => PlateBoxRead(
        text: _unread(json['text'] as String?),
        raw: json['raw'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        crop: json['crop'] as String?,
      );
}

/// A box drawn by dragging from [a] to [b] on a picture shown [area] big, as fractions of the picture
/// ([x0, y0, x1, y1], kept inside it), or null when it is only a slip of the finger.
List<double>? boxFromDrag(({double x, double y}) a, ({double x, double y}) b, ({double w, double h}) area, {double minPixels = 8}) {
  if (area.w <= 0 || area.h <= 0) return null;
  double clamp(double v) => v.clamp(0.0, 1.0);
  final x0 = clamp(a.x / area.w), x1 = clamp(b.x / area.w), y0 = clamp(a.y / area.h), y1 = clamp(b.y / area.h);
  final box = [x0 < x1 ? x0 : x1, y0 < y1 ? y0 : y1, x0 < x1 ? x1 : x0, y0 < y1 ? y1 : y0];
  if ((box[2] - box[0]) * area.w < minPixels || (box[3] - box[1]) * area.h < minPixels) return null;
  return box;
}
