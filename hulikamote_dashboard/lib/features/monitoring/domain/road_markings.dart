import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'crosswalk_quad.dart';
import 'models/road_detect.dart';

/// Which violation takes which road marking, and the zone the marking becomes for it. The markings are drawn once, on the setup picture;
/// each violation that is picked pulls only the ones it needs into its own zones, so the rest of the setup (and the backend) work
/// with zones as they always did. Everything is in the 1920x1080 reference space.
class RoadMarkingMap {
  RoadMarkingMap._();

  /// What each violation takes, for the markings page: the marking, and the violation that uses it.
  static const uses = <(String marking, String violationKey)>[
    ('Crosswalk', 'pedestrian_lane'),
    ('Solid line', 'crossing_solid_line'),
    ('Stop line', 'red_light'),
    ('Lane with a type', 'restricted_lane'),
    ('Road or lane with a direction', 'counterflow'),
    ('Road or lane with a direction', 'illegal_turn'),
    ('Road: national highway', 'tricycle_on_highway'),
    ('Road', 'truck_ban'),
    ('Sidewalk', 'sidewalk_driving'),
  ];

  /// Half the width of the band made around a stop line for "Red light" (the rule needs an area around the line, not only the line).
  static const stopBand = 140.0;

  static List<List<double>> _points(List<Offset> points) => [
    for (final p in points) [p.dx, p.dy],
  ];

  /// The zones the markings make for [violationKey]: none when no marking is meant for it. Every zone carries `marking` (the id of the
  /// marking it came from), so a zone that came from a marking can be told from one the operator drew.
  static List<Map<String, dynamic>> roisFor(String violationKey, List<RoadArea> markings, {Map<String, dynamic>? config}) {
    final zones = <Map<String, dynamic>>[];
    for (final m in markings) {
      switch ((violationKey, m.kind)) {
        case ('pedestrian_lane', 'crosswalk'):
        case ('sidewalk_driving', 'sidewalk'):
        case ('truck_ban', 'road'):
          if (m.polygon.length >= 3) zones.add({'polygon': _points(m.polygon), 'marking': m.id, if (m.kind == 'crosswalk' && m.paint) 'paint': {'stripes': m.stripes, 'wear': m.wear, 'realistic': m.realistic}});
        case ('tricycle_on_highway', 'road'):
          if (m.polygon.length >= 3 && m.roadClass == 'national_highway') zones.add({'polygon': _points(m.polygon), 'marking': m.id});
        case ('crossing_solid_line', 'solid_line'):
          if (m.polygon.length >= 2) {
            zones.add({
              'line': _points(m.polygon),
              'marking': m.id,
              if (m.paint) 'look': {'style': m.style, 'width': m.lineWidth, 'wear': m.wear, 'taper': m.taper, 'realistic': m.realistic},
            });
          }
        case ('red_light', 'stop_line'):
          if (m.polygon.length >= 2) zones.add(_stopZone(m));
        case ('restricted_lane', 'lane'):
          if (m.polygon.length >= 3 && m.laneType != null) {
            zones.add({'polygon': _points(m.polygon), 'lane_type': m.laneType, 'marking': m.id});
          }
        case ('counterflow', 'road' || 'lane'):
          if (m.polygon.length >= 3 && m.flow != null && m.arrow.length >= 2) zones.add(_flowZone(m));
        case ('illegal_turn', 'road' || 'lane'):
          if (m.polygon.length >= 3 && m.flow != null && m.arrow.length >= 2) {
            final zone = _turnZone(m, config);
            if (zone != null) zones.add(zone);
          }
        default:
          break;
      }
    }
    return zones;
  }

  /// The turns that are banned at this camera, as the driver sees them (the two chips of Illegal turn). Missing: left. Empty: none.
  static List<String> bannedTurns(Map<String, dynamic>? config) {
    final raw = config?['banned_turns'];
    if (raw is! List) return const ['left'];
    return [for (final s in raw) if (s == 'left' || s == 'right') s as String];
  }

  /// A road or lane with a direction becomes an Illegal turn zone: the road, stretched a little past its far end (where the turn is made),
  /// the banned sides, the way the road runs (only vehicles that came in along it count: the incoming and the outgoing road judge their
  /// own traffic), and the banned turns as arrows ([turn_arrow_left] / [turn_arrow_right] for the live picture, `ui_vectors` for the
  /// zone editor). Null when no turn is banned.
  static Map<String, dynamic>? _turnZone(RoadArea m, Map<String, dynamic>? config) {
    final banned = bannedTurns(config);
    if (banned.isEmpty) return null;
    final from = m.arrow.first, to = m.arrow.last;
    final run = to - from;
    final len = run.distance;
    if (len < 1) return null;
    final dir = run / len;
    // the road stretched past its far end by a third of its length along the arrow: a turn is made in the junction beyond the road
    var far = 0.0;
    for (final p in m.polygon) {
      far = math.max(far, (p - from).dx * dir.dx + (p - from).dy * dir.dy);
    }
    final reach = math.max(60.0, 0.35 * far);
    final hull = convexHull([...m.polygon, for (final p in m.polygon) p + dir * reach]);
    final side = math.max(120.0, math.min(300.0, 0.3 * len + 60));
    final left = Offset(dir.dy, -dir.dx), right = Offset(-dir.dy, dir.dx);   // as the driver sees them (y runs down the picture)
    List<Offset> bend(Offset lateral) => [to - dir * (side * 0.5), to, to + lateral * side];
    return {
      'polygon': _points(hull),
      'banned_turns': banned,
      'approach': {'x_dir': dir.dx, 'y_dir': dir.dy},
      if (banned.contains('left')) 'turn_arrow_left': _points(bend(left)),
      if (banned.contains('right')) 'turn_arrow_right': _points(bend(right)),
      'vector': {'x_dir': (banned.contains('left') ? left : right).dx, 'y_dir': (banned.contains('left') ? left : right).dy},
      'ui_vectors': [
        if (banned.contains('left')) _points([to, to + left * side]),
        if (banned.contains('right')) _points([to, to + right * side]),
      ],
      'marking': m.id,
    };
  }

  /// A stop line becomes the Red light zone the wizard makes: the stop line (its two ends) and a band of road around it.
  static Map<String, dynamic> _stopZone(RoadArea m) {
    final a = m.polygon.first, b = m.polygon.last;
    final d = b - a;
    final length = d.distance;
    final side = (length < 1 ? const Offset(0, 1) : Offset(-d.dy / length, d.dx / length)) * stopBand;
    return {
      'polygon': _points([a + side, b + side, b - side, a - side]),
      'ui_vector': _points([a, b]),
      'marking': m.id,
    };
  }

  /// A road or lane with a direction becomes a Counterflow zone: its area, and the arrow as the legal way.
  static Map<String, dynamic> _flowZone(RoadArea m) {
    final from = m.arrow.first, to = m.arrow.last;       // a bent arrow counts as the way from its first to its last point
    return {
      'polygon': _points(m.polygon),
      'vector': {'x_dir': to.dx - from.dx, 'y_dir': to.dy - from.dy},
      'ui_vector': _points([from, to]),
      // a bent arrow (a road marked with many points): the rule judges each stretch against its own direction
      if (m.arrow.length > 2) 'path': _points(m.arrow),
      'marking': m.id,
    };
  }
}
