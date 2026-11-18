import 'dart:convert';

import '../../forensic/domain/analysis_draft.dart';
import 'models/road_detect.dart';
import 'road_markings.dart';

/// The violations picked on a live picture, and the road markings drawn on it. A live camera has no recording to search, so a solid
/// line cannot be "found in the video when the analysis starts": it must be drawn (or marked).
class LiveSetupDraft extends AnalysisDraft {
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

  /// violation key -> what was pulled into its zones the last time. A zone that came from a marking is changed by a new sync only while
  /// it still is what was pulled: once the operator edits or deletes it in the rules step, it is theirs.
  final Map<String, String> _pulled = {};

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
      list.addAll(RoadMarkingMap.roisFor(key, markings));
      _pulled[key] = _signature(key);
    }
  }

  @override
  Map<String, dynamic> buildConfig({String? activePlateModel}) => {
    ...super.buildConfig(activePlateModel: activePlateModel),
    'road_markings': [for (final m in markings) m.toJson()],   // kept with the setup: opened again, the markings are still there
  };
}
