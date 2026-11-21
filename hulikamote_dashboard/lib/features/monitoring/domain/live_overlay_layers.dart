import '../../forensic/domain/violation_catalog.dart';

/// One checklist row of the Live Monitor's "Layers": the overlay objects (signs, painted crosswalks, painted lines) of ONE violation.
/// Switching it off hides them on the live picture; the rule still judges.
class OverlayLayer {
  const OverlayLayer(this.key, this.label, this.count, {this.hint});

  final String key; // the violation key (what the backend hides)
  final String label; // "Restricted lane: signs"
  final int count;

  /// What the row says under its name; null = the count and "on the video".
  final String? hint;

  /// The Layers key of the banned-turn arrows (the backend hides them from the live zones, see routers/stream.py).
  static const turnArrowsKey = 'illegal_turn:arrows';

  /// The Layers key of the vehicle paths (the light line behind every vehicle, drawn while one of [pathRules] is on; the backend hides them).
  static const pathsKey = 'crossing_solid_line:paths';

  /// The rules that judge a vehicle from the way it drove: they share the light path line (the same list as the backend's PATH_RULES).
  static const pathRules = ['crossing_solid_line', 'illegal_turn', 'swerving', 'overtaking_on_right'];

  /// The layers of a live setup (GET /settings/live/setup): one for each switched-on violation that has overlay objects. A violation that is
  /// switched off, or has none, has no row, so rows appear and go with the violations.
  static List<OverlayLayer> of(Map<String, dynamic> setup) {
    final per = setup['per_violation_configs'];
    final out = <OverlayLayer>[];
    for (final raw in (setup['active_violations'] as List? ?? const [])) {
      final key = '$raw';
      final cfg = per is Map && per[key] is Map ? Map<String, dynamic>.from(per[key] as Map) : const <String, dynamic>{};
      final rois = [for (final z in (cfg['rois'] as List? ?? const [])) if (z is Map) z];
      final signs = (cfg['signs'] as List?)?.length ?? 0;
      final (count, noun) = switch (key) {
        'pedestrian_lane' => (((cfg['crosswalks'] as List?)?.length ?? 0) + rois.where((z) => z['paint'] != null && z['paint'] != false).length, 'painted crosswalks'),
        'crossing_solid_line' => (rois.where((z) => z['look'] is Map).length, 'painted lines'),
        _ => (signs, 'signs'),
      };
      if (count > 0) out.add(OverlayLayer(key, '${ViolationCatalog.of(key).label}: $noun', count));
      if (key == 'illegal_turn') {                      // the banned-turn arrows of the marked roads: their own switch (the backend key has a suffix)
        final arrows = rois.where((z) => z['turn_arrow_left'] != null || z['turn_arrow_right'] != null).length;
        if (arrows > 0) out.add(OverlayLayer(turnArrowsKey, 'Illegal turn: banned-turn arrows', arrows));
      }
    }
    final onPaths = [for (final raw in (setup['active_violations'] as List? ?? const [])) if (pathRules.contains('$raw')) ViolationCatalog.of('$raw').label];
    if (onPaths.isNotEmpty) {                          // one switch for the light path line: the rules that follow a vehicle's way share it
      out.add(OverlayLayer(pathsKey, 'Vehicle paths', 0, hint: 'The light line behind every vehicle (${onPaths.join(', ')})'));
    }
    return out;
  }
}
