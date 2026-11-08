/// One plate's demerit counter: one point for every violation a reviewer confirmed (backend: demerit_points.py).
class DemeritEntry {
  const DemeritEntry({required this.plate, required this.points, this.byClass = const {}, this.lastAt});

  final String plate;
  final int points;

  /// Points split by violation key, e.g. `{no_helmet: 2, red_light: 1}`.
  final Map<String, int> byClass;
  final DateTime? lastAt;

  factory DemeritEntry.fromJson(Map<String, dynamic> json) => DemeritEntry(
        plate: json['plate'] as String? ?? '',
        points: (json['points'] as num?)?.toInt() ?? 0,
        byClass: {
          for (final e in (json['by_class'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toInt(),
        },
        lastAt: DateTime.tryParse(json['last_at'] as String? ?? '')?.toLocal(),
      );
}

/// A confirmed ticket that gave a point.
class DemeritTicket {
  const DemeritTicket({required this.id, required this.cls, this.at});

  final String id;
  final String cls;
  final DateTime? at;

  factory DemeritTicket.fromJson(Map<String, dynamic> json) => DemeritTicket(
        id: json['id'] as String? ?? '',
        cls: json['cls'] as String? ?? '',
        at: DateTime.tryParse(json['timestamp'] as String? ?? '')?.toLocal(),
      );
}

/// One plate's counter plus the tickets behind it, newest first.
class DemeritDetail {
  const DemeritDetail({required this.entry, required this.tickets});

  final DemeritEntry entry;
  final List<DemeritTicket> tickets;

  factory DemeritDetail.fromJson(Map<String, dynamic> json) => DemeritDetail(
        entry: DemeritEntry.fromJson(json),
        tickets: [
          for (final t in json['violations'] as List? ?? const []) DemeritTicket.fromJson(Map<String, dynamic>.from(t as Map)),
        ],
      );
}
