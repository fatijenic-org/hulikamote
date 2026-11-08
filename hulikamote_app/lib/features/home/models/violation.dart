import 'dart:convert';

class Violation {
  final String id;
  final String cls;
  final double confidence;
  final String timestamp;
  final String imagePath;

  /// The plate the ticket was written for, as the system has it ("" when unknown).
  final String plate;

  /// File names of every photo of this ticket on the laptop.
  final List<String> evidencePaths;

  const Violation({
    required this.id,
    required this.cls,
    required this.confidence,
    required this.timestamp,
    required this.imagePath,
    this.plate = '',
    this.evidencePaths = const [],
  });

  factory Violation.fromJson(Map<String, dynamic> json) => Violation(
        id: json['id'] as String,
        cls: json['cls'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        timestamp: json['timestamp'] as String,
        imagePath: json['image_path'] as String? ?? '',
        plate: _plate(json['plate_text']),
        evidencePaths: _frames(json['evidence_paths']),
      );

  /// A ticket saved on the phone by [toJson] (the photo paths are kept exactly as they were).
  factory Violation.fromCache(Map<String, dynamic> json) => Violation(
        id: json['id'] as String,
        cls: json['cls'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        timestamp: json['timestamp'] as String,
        imagePath: json['image_path'] as String? ?? '',
        plate: json['plate'] as String? ?? '',
        evidencePaths: [for (final f in json['frames'] as List? ?? const []) f as String],
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'cls': cls, 'confidence': confidence, 'timestamp': timestamp, 'image_path': imagePath, 'plate': plate, 'frames': evidencePaths,
      };

  static String _plate(dynamic raw) {
    final text = '${raw ?? ''}'.trim();
    return const {'', 'unidentified', 'no_plate_found'}.contains(text) ? '' : text;
  }

  /// The laptop stores the list as JSON text; names are reduced to the bare file name.
  static List<String> _frames(dynamic raw) {
    try {
      final list = raw is String ? jsonDecode(raw) : raw;
      if (list is! List) return const [];
      return [for (final p in list) p.toString().split(RegExp(r'[\\/]')).last];
    } catch (_) {
      return const [];
    }
  }

  /// The short code the e-mail and the notice call this ticket by.
  String get caseNo => id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

  DateTime? get time => DateTime.tryParse(timestamp)?.toLocal();

  String get displayClass => cls
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class ViolationPage {
  final int total;
  final List<Violation> items;

  const ViolationPage({required this.total, required this.items});

  factory ViolationPage.fromJson(Map<String, dynamic> json) => ViolationPage(
        total: json['total'] as int,
        items: (json['items'] as List)
            .map((e) => Violation.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
