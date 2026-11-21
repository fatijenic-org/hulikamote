/// A saved violation setup of the Live Monitor, as the list shows it: GET /settings/setup-presets?hash=...
/// The setup itself comes with GET /settings/setup-presets/{id} (its `config`).
class SetupPreset {
  const SetupPreset({
    required this.id,
    required this.name,
    required this.violations,
    required this.videoHash,
    required this.videoName,
    required this.match,
    required this.updated,
  });

  final String id;
  final String name;
  final List<String> violations; // the violation keys that are on
  final String videoHash;
  final String videoName;
  final bool match; // made for the video that is in use now
  final DateTime updated;

  factory SetupPreset.fromJson(Map<String, dynamic> json) => SetupPreset(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    violations: [for (final v in (json['violations'] as List? ?? const [])) '$v'],
    videoHash: json['video_hash'] as String? ?? '',
    videoName: json['video_name'] as String? ?? '',
    match: json['match'] == true,
    updated: DateTime.fromMillisecondsSinceEpoch((((json['updated'] as num?) ?? 0) * 1000).round()),
  );
}
