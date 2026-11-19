/// A saved road configuration (the road markings of the live setup under a name), as the list shows it: GET /settings/road-presets.
/// The markings themselves come with GET /settings/road-presets/{id}.
class RoadPreset {
  const RoadPreset({required this.id, required this.name, required this.count, required this.updated});

  final String id;
  final String name;
  final int count; // how many markings it holds
  final DateTime updated;

  factory RoadPreset.fromJson(Map<String, dynamic> json) => RoadPreset(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? (json['markings'] as List?)?.length ?? 0,
    updated: DateTime.fromMillisecondsSinceEpoch((((json['updated'] as num?) ?? 0) * 1000).round()),
  );
}
