import 'dart:convert';

class Violation {
  final String id;
  final String cls;
  final double confidence;
  final String timestamp;
  final String imagePath;
  final String? userName;
  final int trackId;
  final List<String> evidencePaths;

  /// The review decision as the backend stores it: pending, approved or rejected.
  final String status;

  const Violation({
    required this.id,
    required this.cls,
    required this.confidence,
    required this.timestamp,
    required this.imagePath,
    this.userName,
    this.trackId = -1,
    this.evidencePaths = const [],
    this.status = 'pending',
  });

  factory Violation.fromJson(Map<String, dynamic> json) => Violation(
    id: json['id'] as String,
    cls: json['cls'] as String,
    confidence: (json['confidence'] as num).toDouble(),
    timestamp: json['timestamp'] as String,
    imagePath: json['image_path'] as String? ?? '',
    userName: json['user_name'] as String?,
    trackId: (json['track_id'] as num?)?.toInt() ?? -1,
    evidencePaths: _parseEvidencePaths(json['evidence_paths']),
    status: json['status'] as String? ?? 'pending',
  );

  static List<String> _parseEvidencePaths(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        return const [];
      }
    }
    return const [];
  }

  String get displayClass => cls
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String get confidenceLabel => '${(confidence * 100).toStringAsFixed(0)}%';
}

class ViolationPage {
  final int total;
  final int page;
  final int size;
  final List<Violation> items;

  const ViolationPage({
    required this.total,
    required this.page,
    required this.size,
    required this.items,
  });

  factory ViolationPage.fromJson(Map<String, dynamic> json) => ViolationPage(
    total: json['total'] as int,
    page: json['page'] as int,
    size: json['size'] as int,
    items: (json['items'] as List)
        .map((e) => Violation.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
