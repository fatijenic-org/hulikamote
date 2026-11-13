import 'package:flutter/material.dart';

/// Where a violation sits in the picker; also decides its accent colour.
enum ViolationGroup {
  movement('Movement & position', Color(0xFF64B5F6)),
  signals('Signals & signs', Color(0xFFFFB74D)),
  vehicle('Vehicle & riders', Color(0xFFBA9BFF));

  final String title;
  final Color color;
  const ViolationGroup(this.title, this.color);
}

/// One violation the analyzer can look for: plain-language label, what it means,
/// and what the operator has to provide (a drawn zone, a trained model).
class ViolationInfo {
  final String key; // backend key, e.g. `restricted_lane`
  final String label;
  final String blurb;
  final ViolationGroup group;
  final IconData icon;

  /// Needs at least one zone drawn on the video frame.
  final bool needsZone;

  /// Needs a trained model of this catalog type (`helmet`, `cabin`).
  final String? needsModel;

  /// Shown in the zone step: what to draw and why.
  final String zoneHint;

  /// Offered in the wizard (older violations can still be displayed in results).
  final bool selectable;

  const ViolationInfo({
    required this.key,
    required this.label,
    required this.blurb,
    required this.group,
    required this.icon,
    this.needsZone = false,
    this.needsModel,
    this.zoneHint = '',
    this.selectable = true,
  });

  Color get color => group.color;
}

/// All violations, in the order the wizard shows them.
class ViolationCatalog {
  ViolationCatalog._();

  static const List<ViolationInfo> all = [
    ViolationInfo(
      key: 'counterflow',
      label: 'Counterflow',
      blurb: 'Drives against the legal direction of the lane.',
      group: ViolationGroup.movement,
      icon: Icons.u_turn_left,
      needsZone: true,
      zoneHint:
          'A zone is optional: with none drawn the whole picture is watched and the legal direction is learned from the traffic. '
          'To set it yourself, cover the lane, then draw an arrow in the LEGAL direction of travel.',
    ),
    ViolationInfo(
      key: 'restricted_lane',
      label: 'Restricted lane',
      blurb:
          'A vehicle type that is not allowed in a reserved lane (e.g. bus lane).',
      group: ViolationGroup.movement,
      icon: Icons.directions_bus,
      needsZone: true,
      zoneHint:
          'A zone is optional: with none drawn the whole picture is the lane. To limit the rule to one lane, cover it. '
          'Tick which vehicle types ARE allowed, or place a sign on the road (Bus lane, No trucks, ...) to say it.',
    ),
    ViolationInfo(
      key: 'illegal_parking',
      label: 'Illegal parking',
      blurb: 'Stays stopped inside a no-parking zone for too long.',
      group: ViolationGroup.movement,
      icon: Icons.local_parking,
      needsZone: true,
      zoneHint:
          'Mark where parking is banned: place a box on the picture (a no-parking sign, a fire hydrant, a fire station driveway, a corner, '
          'a private driveway; move it, resize it: its box is the area) or cover the area. Then set how long a vehicle may stop there. '
          'Crosswalk, junction and double parking have their own rules.',
    ),
    ViolationInfo(
      key: 'pedestrian_lane',
      label: 'Pedestrian lane blocked',
      blurb: 'Stops on a crosswalk.',
      group: ViolationGroup.movement,
      icon: Icons.directions_walk,
      needsZone: true,
      zoneHint:
          'Draw over the crosswalk. Vehicles stopped on it past the limit are flagged.',
    ),
    ViolationInfo(
      key: 'blocking_intersection',
      label: 'Blocking the intersection',
      blurb: 'Stops inside the junction box and blocks the cross traffic.',
      group: ViolationGroup.movement,
      icon: Icons.block,
      needsZone: true,
      zoneHint:
          'Draw over the junction box. A vehicle that stands still inside it past the limit is flagged.',
    ),
    ViolationInfo(
      key: 'illegal_turn',
      label: 'Illegal turn',
      blurb: 'Turns where turning is prohibited.',
      group: ViolationGroup.movement,
      icon: Icons.turn_slight_left,
      needsZone: true,
      zoneHint:
          'A zone is optional: with none drawn the whole picture is watched for the turns you ban (set them below). '
          'To limit the rule, cover the approach AND the turn area, then draw an arrow toward the turn that is NOT allowed.',
    ),
    ViolationInfo(
      key: 'illegal_u_turn',
      label: 'Illegal U-turn',
      blurb: 'Turns right round where a U-turn is prohibited.',
      group: ViolationGroup.movement,
      icon: Icons.u_turn_right,
      needsZone: true,
      zoneHint:
          'A zone is optional: with none drawn the whole picture is watched. To limit the rule, draw over the road area where U-turns '
          'are NOT allowed. A vehicle that turns right round inside it is flagged.',
    ),
    ViolationInfo(
      key: 'swerving',
      label: 'Swerving',
      blurb: 'Weaves from side to side.',
      group: ViolationGroup.movement,
      icon: Icons.waves,
      needsZone: true,
      zoneHint: 'A zone is optional: with none drawn the whole picture is watched. To limit the rule, draw over the road section to watch for side-to-side weaving.',
    ),
    ViolationInfo(
      key: 'crossing_solid_line',
      label: 'Crossing a solid line',
      blurb: 'Drives over a solid line that must not be crossed.',
      group: ViolationGroup.movement,
      icon: Icons.horizontal_rule,
      needsZone: true,
      zoneHint:
          'Nothing has to be drawn: the painted solid lines are found in the video. To choose a line yourself, click along it '
          '(a point at every bend, so a curve works). A vehicle that drives over it is flagged.',
    ),
    ViolationInfo(
      key: 'illegal_loading',
      label: 'Illegal loading / unloading',
      blurb: 'A bus, jeepney, tricycle or truck stops to load or unload where it is not allowed.',
      group: ViolationGroup.movement,
      icon: Icons.no_transfer,
      needsZone: true,
      zoneHint:
          'Place a no-loading sign on the picture (move it, resize it: its box is the no-loading area) or draw the area, '
          'then set how long a vehicle may stop and which types are judged.',
    ),
    ViolationInfo(
      key: 'truck_ban',
      label: 'Truck ban / truck lane',
      blurb: 'A truck on a road or lane that is closed to trucks.',
      group: ViolationGroup.movement,
      icon: Icons.local_shipping_outlined,
      needsZone: true,
      zoneHint:
          'A zone is optional: with none drawn the whole picture counts as a road closed to trucks. To limit the ban, draw over the road or lane '
          'closed to trucks. For a ban that only applies at certain hours, analyse footage from those hours.',
    ),
    ViolationInfo(
      key: 'tricycle_on_highway',
      label: 'Tricycle on a national highway',
      blurb: 'A tricycle on a highway where tricycles are not allowed (DILG MC 2020-036).',
      group: ViolationGroup.movement,
      icon: Icons.electric_rickshaw,
      needsZone: true,
      zoneHint:
          'A zone is optional: with none drawn, the whole picture counts as a road where tricycles are banned, so tick this rule only for '
          'a camera that watches such a road (a national highway with no exemption in the city\'s route plan). If the view also shows a side '
          'street or an exempted section, draw only the banned part. Needs the Philippine vehicle model that knows "tricycle".',
    ),
    ViolationInfo(
      key: 'sidewalk_driving',
      label: 'Driving on the sidewalk',
      blurb: 'A moving vehicle on the sidewalk or in a bike lane.',
      group: ViolationGroup.movement,
      icon: Icons.do_not_step,
      needsZone: true,
      zoneHint:
          'Draw over the sidewalk or bike lane. A vehicle that keeps moving inside it for 1.5 s is flagged; a parked one is not.',
    ),
    ViolationInfo(
      key: 'double_parking',
      label: 'Double parking',
      blurb: 'Stands in the travel lane beside a parked vehicle while traffic passes.',
      group: ViolationGroup.movement,
      icon: Icons.local_taxi,
      needsZone: true,
      zoneHint:
          'A zone is optional: with none drawn the whole picture is watched. To limit the rule, draw over the one travel lane next to the kerb '
          '(not the whole road). Needs moving traffic in that lane to tell it from a queue.',
    ),
    ViolationInfo(
      key: 'red_light',
      label: 'Red light',
      blurb: 'Crosses the stop line while the light is red.',
      group: ViolationGroup.signals,
      icon: Icons.traffic,
      needsZone: true,
      zoneHint:
          'Cover the approach and junction, draw the stop line across your approach lanes only, '
          'then box the real traffic light or use a virtual light.',
    ),
    ViolationInfo(
      key: 'disregarding_signs',
      label: 'Disregarding signs',
      blurb: 'No entry, no turn, no stopping, banned vehicle or stop sign.',
      group: ViolationGroup.signals,
      icon: Icons.do_not_disturb_on,
      needsZone: true,
      zoneHint:
          'One zone per sign. Pick the sign type first, then draw where it applies.',
    ),
    ViolationInfo(
      key: 'signal_light',
      label: 'No turn signal',
      blurb: 'Turns without a blinking indicator.',
      group: ViolationGroup.signals,
      icon: Icons.flare,
      needsZone: true,
      zoneHint:
          'A zone is optional: with none drawn the whole picture is watched. To limit the rule, cover the approach AND the turn area. '
          'A turn here with no blinking indicator is flagged.',
    ),
    ViolationInfo(
      key: 'overloading',
      label: 'Overloading',
      blurb: 'More riders on a motorcycle than allowed.',
      group: ViolationGroup.vehicle,
      icon: Icons.groups,
    ),
    ViolationInfo(
      key: 'pickup_passengers',
      label: 'Passengers in a pickup bed',
      blurb: 'People riding in the open back of a moving pickup or truck (RA 4136).',
      group: ViolationGroup.vehicle,
      icon: Icons.local_shipping,
    ),
    ViolationInfo(
      key: 'riding_outside_vehicle',
      label: 'Riding on the roof / hanging on',
      blurb: 'People on the roof of, or hanging off, a moving bus, jeepney or truck (RA 4136).',
      group: ViolationGroup.vehicle,
      icon: Icons.directions_bus_filled,
    ),
    ViolationInfo(
      key: 'no_helmet',
      label: 'No helmet',
      blurb: 'A rider without a helmet.',
      group: ViolationGroup.vehicle,
      icon: Icons.sports_motorsports,
      needsModel: 'helmet',
    ),
    ViolationInfo(
      key: 'no_plate',
      label: 'No plate',
      blurb: 'A vehicle with no license plate at all.',
      group: ViolationGroup.vehicle,
      icon: Icons.no_photography,
    ),
    ViolationInfo(
      key: 'no_seatbelt',
      label: 'No seatbelt',
      blurb: 'A driver without a seatbelt.',
      group: ViolationGroup.vehicle,
      icon: Icons.airline_seat_recline_normal,
      needsModel: 'cabin',
    ),
    ViolationInfo(
      key: 'missing_side_mirror',
      label: 'Missing side mirror',
      blurb: 'A motorcycle missing a mirror.',
      group: ViolationGroup.vehicle,
      icon: Icons.flip,
      needsModel: 'cabin',
    ),
    ViolationInfo(
      key: 'distracted_driving',
      label: 'Phone use',
      blurb: 'A driver using a phone.',
      group: ViolationGroup.vehicle,
      icon: Icons.phone_android,
      needsModel: 'cabin',
    ),
  ];

  static final Map<String, ViolationInfo> _byKey = {
    for (final v in all) v.key: v,
  };

  /// Info for any backend key; unknown keys get a readable fallback label.
  static ViolationInfo of(String key) =>
      _byKey[key] ??
      ViolationInfo(
        key: key,
        label: key.isEmpty
            ? 'Unknown'
            : key
                  .split('_')
                  .map(
                    (w) => w.isEmpty
                        ? w
                        : '${w[0].toUpperCase()}${w.substring(1)}',
                  )
                  .join(' '),
        blurb: '',
        group: ViolationGroup.vehicle,
        icon: Icons.report_problem_outlined,
        selectable: false,
      );

  static List<ViolationInfo> get selectable =>
      all.where((v) => v.selectable).toList();

  static List<ViolationInfo> inGroup(ViolationGroup g) =>
      selectable.where((v) => v.group == g).toList();

  /// Sign types of `disregarding_signs`: label and whether the zone also needs an arrow / line.
  static const Map<String, ({String label, bool arrow})> signs = {
    'no_entry': (label: 'No entry / one way', arrow: true),
    'no_turn': (label: 'No left / right / U-turn', arrow: true),
    'no_stopping': (label: 'No stopping / loading', arrow: false),
    'vehicle_ban': (label: 'Vehicle type banned', arrow: false),
    'stop': (label: 'Stop sign', arrow: true),
  };

  /// Violations whose zone also needs an arrow (or a line) besides the polygon.
  static const Set<String> arrowViolations = {
    'counterflow',
    'illegal_turn',
    'red_light',
    'crossing_solid_line',
  };

  /// Of those, the ones whose "arrow" is really a line the vehicles must not cross (drawn as a line, not an arrow).
  static const Set<String> lineViolations = {'red_light', 'crossing_solid_line'};

  /// Vehicle types offered in allowed / banned pickers.
  static const List<String> vehicleTypes = [
    'bus',
    'motorcycle',
    'car',
    'truck',
    'tricycle',
    'bicycle',
  ];
}
