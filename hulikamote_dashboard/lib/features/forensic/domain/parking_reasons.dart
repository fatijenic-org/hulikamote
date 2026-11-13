/// Why parking is banned in a marked area: the sub-conditions of "Illegal parking".
///
/// Source: Republic Act No. 4136 (Land Transportation and Traffic Code), Section 46, items (a) to (h). The backend's
/// engine/parking_reasons.py is the source of truth; keep the two the same.
///
/// Five of the eight places are marked on the picture by the operator as a box (the box IS the banned area, see loading_signs.dart).
/// The other three have their own rules, so they are only named here and the operator can switch those rules on.
class ParkingReason {
  const ParkingReason({
    required this.key,
    required this.item,
    required this.label,
    required this.short,
    required this.text,
    required this.hint,
    required this.lines,
    this.meters,
  });

  final String key; // sign | hydrant | fire_station | corner | driveway
  final String item; // the letter of Section 46
  final String label; // for the list of placed signs
  final String short; // for the chip
  final String text; // the place, in words
  final String hint; // how to size the box
  final List<String> lines; // the two lines drawn on the sign
  final int? meters;
}

/// A Section 46 item that another rule judges.
class ParkingOtherRule {
  const ParkingOtherRule({required this.item, required this.text, required this.ruleKey});

  final String item;
  final String text;
  final String ruleKey;
}

class ParkingReasons {
  ParkingReasons._();

  static const String defaultKind = 'sign';
  static const String source = 'RA 4136 (Land Transportation and Traffic Code), Section 46';
  static const String fireCodeNote =
      'The Fire Code (RA 9514, Section 8(d)) also bans blocking fire lanes and hydrant access. It gives no distance. The 4 m comes from RA 4136.';

  static const List<ParkingReason> all = [
    ParkingReason(
      key: 'sign',
      item: 'h',
      label: 'Official no-parking sign',
      short: 'No-parking sign',
      text: 'Where an official no-parking sign stands',
      hint: 'Put the box where the real sign stands. The box is the stretch of road the sign covers.',
      lines: ['NO', 'PARKING'],
    ),
    ParkingReason(
      key: 'hydrant',
      item: 'e',
      meters: 4,
      label: 'Fire hydrant (4 m)',
      short: 'Fire hydrant',
      text: 'Within 4 m of a fire hydrant',
      hint: 'Centre the box on the hydrant. Make it about 8 m long: 4 m each side. A car is about 4.5 m long.',
      lines: ['FIRE HYDRANT', 'NO PARKING'],
    ),
    ParkingReason(
      key: 'fire_station',
      item: 'd',
      meters: 4,
      label: 'Fire station driveway (4 m)',
      short: 'Fire station driveway',
      text: 'Within 4 m of the driveway entrance to a fire station',
      hint: 'Centre the box on the driveway entrance. About 8 m long: 4 m each side.',
      lines: ['FIRE STATION', 'NO PARKING'],
    ),
    ParkingReason(
      key: 'corner',
      item: 'c',
      meters: 6,
      label: 'Corner, curb lines meet (6 m)',
      short: 'Corner',
      text: 'Within 6 m of the corner (where the curb lines meet)',
      hint: 'Start the box at the corner where the two curb lines meet. Run it about 6 m (one and a half cars) along the street.',
      lines: ['CORNER', 'NO PARKING'],
    ),
    ParkingReason(
      key: 'driveway',
      item: 'f',
      label: 'Private driveway',
      short: 'Private driveway',
      text: 'In front of a private driveway',
      hint: 'Cover the strip of road in front of the driveway.',
      lines: ['DRIVEWAY', 'NO PARKING'],
    ),
  ];

  /// Section 46 items that other rules judge, in the order of the Section.
  static const List<ParkingOtherRule> others = [
    ParkingOtherRule(item: 'a', text: 'Within an intersection', ruleKey: 'blocking_intersection'),
    ParkingOtherRule(item: 'b', text: 'On a crosswalk', ruleKey: 'pedestrian_lane'),
    ParkingOtherRule(item: 'g', text: 'On the roadway side of a parked vehicle (double parking)', ruleKey: 'double_parking'),
  ];

  /// The reason with this key; a missing or unknown key is the official sign.
  static ParkingReason of(String? key) => all.firstWhere((r) => r.key == key, orElse: () => all.first);
}
