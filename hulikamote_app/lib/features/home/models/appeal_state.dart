import 'package:flutter/material.dart';

import '../../../core/ui/widgets.dart';

/// Where a ticket stands with the motorist's appeal, in words and a look. `status` is what the system sends:
/// null (no appeal), pending, accepted or rejected.
class AppealState {
  const AppealState._(this.status, this.label, this.tone, this.icon, this.explain);

  final String? status;

  /// Short, for a chip.
  final String label;
  final Tone tone;
  final IconData icon;

  /// One sentence for the ticket page.
  final String explain;

  factory AppealState.of(String? status) => switch (status) {
        'pending' => const AppealState._('pending', 'Appeal sent', Tone.warning, Icons.hourglass_top_rounded, 'A reviewer has not decided yet.'),
        'accepted' => const AppealState._('accepted', 'Appeal accepted', Tone.success, Icons.check_circle_outline, 'A reviewer accepted your appeal.'),
        'rejected' => const AppealState._('rejected', 'Appeal rejected', Tone.danger, Icons.cancel_outlined, 'A reviewer did not accept your appeal.'),
        _ => const AppealState._(null, 'Can appeal', Tone.info, Icons.gavel_rounded, 'You can appeal this ticket once.'),
      };

  /// No appeal yet, so the motorist may still send one.
  bool get open => status == null;
}

/// A picture for each kind of violation.
IconData iconForViolation(String cls) {
  final first = cls.split(',').first.trim();
  return switch (first) {
    'no_helmet' => Icons.sports_motorsports_outlined,
    'counterflow' => Icons.swap_vert_rounded,
    'red_light' => Icons.traffic_outlined,
    'illegal_parking' || 'double_parking' => Icons.local_parking_rounded,
    'no_seatbelt' => Icons.airline_seat_recline_normal_outlined,
    'no_plate' => Icons.credit_card_off_outlined,
    'overloading' || 'pickup_passengers' || 'riding_outside_vehicle' => Icons.groups_outlined,
    'illegal_turn' || 'illegal_u_turn' => Icons.u_turn_left_rounded,
    'restricted_lane' || 'truck_ban' || 'banned_in_zone' => Icons.block_rounded,
    'crossing_solid_line' => Icons.linear_scale_rounded,
    _ => Icons.report_problem_outlined,
  };
}
