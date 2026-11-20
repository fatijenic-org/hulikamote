import 'dart:convert';

import 'dart:ui' show Offset;

import '../../forensic/domain/analysis_draft.dart';
import '../../forensic/domain/marking_shape.dart';
import 'models/road_detect.dart';
import 'road_markings.dart';

/// The violations picked on a live picture, and the road markings drawn on it. A live camera has no recording to search, so a solid
/// line cannot be "found in the video when the analysis starts": it must be drawn (or marked).
class LiveSetupDraft extends AnalysisDraft {
  /// A live picture, not a video file: the time is this computer's clock, and nothing can be read from a video path.
  @override
  bool get isLive => true;

  @override
  bool findsLinesItself(String key) => false;

  /// The solid-line editor's "find the lines automatically" switch starts OFF on a live picture.
  @override
  Map<String, dynamic> config(String key) {
    final cfg = super.config(key);
    if (key == 'crossing_solid_line') cfg.putIfAbsent('auto_lines', () => false);
    return cfg;
  }

  /// The road markings made on the setup picture (1920x1080 reference space). They are drawn once; [syncMarkings] hands each picked
  /// violation the ones it needs, as zones.
  List<RoadArea> markings = const [];

  @override
  List<MarkingShape> get markingShapes {
    final count = <String, int>{};
    return [
      for (final m in markings)
        if (!m.isLine && m.polygon.length >= 3 && m.kind != 'solid_line')
          () {
            final n = count.update(m.kind, (v) => v + 1, ifAbsent: () => 1);
            final type = m.kind == 'lane' && m.laneType != null ? RoadArea.laneTypes[m.laneType] : null;
            return MarkingShape(
              id: m.id,
              kind: m.kind,
              label: ['${RoadArea.labelOf(m.kind)} $n', ?type].join(' · '),
              polygon: [for (final p in m.polygon) Offset(p.dx, p.dy)],
              laneType: m.kind == 'lane' ? m.laneType : null,
            );
          }(),
    ];
  }

  /// violation key -> what was pulled into its zones the last time. A zone that came from a marking is changed by a new sync only while
  /// it still is what was pulled: once the operator edits or deletes it in the rules step, it is theirs.
  final Map<String, String> _pulled = {};

  String _bannedSeen = '';

  /// A change of the banned turns (the two chips of Illegal turn) changes the zones the marked roads made for it.
  @override
  void touch() {
    if (selection.contains('illegal_turn')) {
      final now = jsonEncode(config('illegal_turn')['banned_turns']);
      if (now != _bannedSeen) {
        _bannedSeen = now;
        syncMarkings();
      }
    }
    super.touch();
  }

  /// Illegal turn: what was read from the marked roads, in words (which roads, which turns), so the operator sees what will be judged.
  @override
  String? roadHint(String key) {
    if (key != 'illegal_turn') return null;
    final banned = RoadMarkingMap.bannedTurns(config(key));
    if (banned.isEmpty) return 'No turn is banned: the whole-picture check and the marked roads are off. Signs and drawn zones still work.';
    final roads = [for (final m in markings) if (m.hasDirection && m.flow != null && m.arrow.length >= 2) m];
    if (roads.isEmpty) {
      return 'No road with a direction is marked in the Road step, so the whole picture is watched. Mark a road and its arrow to judge each road on its own.';
    }
    final names = [
      for (final (i, m) in roads.indexed) '${m.flow == 'in' ? 'incoming' : 'outgoing'} ${m.kind == 'lane' ? 'lane' : 'road'} ${i + 1}',
    ];
    return 'Read from your road setup: ${names.join(', ')}. Banned: ${banned.join(' and ')} turn. A turn is judged on the road the vehicle '
        'drove along, as the driver sees left and right. The banned turns are drawn as orange arrows.';
  }

  void setMarkings(List<RoadArea> list) {
    markings = List.unmodifiable(list);
    syncMarkings();
    notifyListeners();
  }

  static bool _fromMarking(dynamic zone) => zone is Map && zone.containsKey('marking');

  String _signature(String key) => jsonEncode([
    for (final z in zones(key))
      if (_fromMarking(z)) z,
  ]);

  /// After a saved setup was loaded: the zones in it that came from markings are what was pulled, so a new sync may refresh them.
  void rememberPulled(String key) => _pulled[key] = _signature(key);

  /// Pulls the markings into the zones of every PICKED violation (a violation that is not picked takes nothing).
  void syncMarkings() {
    for (final key in selection) {
      final now = _signature(key);
      final before = _pulled[key];
      final untouched = before == null ? now == '[]' : now == before;
      if (!untouched) continue;                                  // the operator changed them: they stay as they are
      final list = zones(key);
      list.removeWhere(_fromMarking);
      list.addAll(RoadMarkingMap.roisFor(key, markings, config: config(key)));
      _pulled[key] = _signature(key);
    }
  }

  @override
  Map<String, dynamic> buildConfig({String? activePlateModel}) => {
    ...super.buildConfig(activePlateModel: activePlateModel),
    'road_markings': [for (final m in markings) m.toJson()],   // kept with the setup: opened again, the markings are still there
  };
}
