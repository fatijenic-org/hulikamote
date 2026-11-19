import 'dart:ui' show Offset;

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
  static List<Map<String, dynamic>> roisFor(String violationKey, List<RoadArea> markings) {
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
          if (m.polygon.length >= 2) zones.add({'line': _points(m.polygon), 'marking': m.id});
        case ('red_light', 'stop_line'):
          if (m.polygon.length >= 2) zones.add(_stopZone(m));
        case ('restricted_lane', 'lane'):
          if (m.polygon.length >= 3 && m.laneType != null) {
            zones.add({'polygon': _points(m.polygon), 'lane_type': m.laneType, 'marking': m.id});
          }
        case ('counterflow', 'road' || 'lane'):
          if (m.polygon.length >= 3 && m.flow != null && m.arrow.length >= 2) zones.add(_flowZone(m));
        default:
          break;
      }
    }
    return zones;
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
