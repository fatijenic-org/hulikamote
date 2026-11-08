import 'package:flutter/material.dart';

/// Violation types selectable in the video analysis pipeline builder.
enum ViolationKind { counterflow, illegalParking, restrictedLane, noHelmet, noPlate }

extension ViolationKindX on ViolationKind {
  String get label {
    switch (this) {
      case ViolationKind.counterflow:
        return 'Counterflow (Wrong Way)';
      case ViolationKind.illegalParking:
        return 'Illegal Parking';
      case ViolationKind.restrictedLane:
        return 'Restricted Lane (Bus Lane)';
      case ViolationKind.noHelmet:
        return 'No Helmet';
      case ViolationKind.noPlate:
        return 'No Plate Number';
    }
  }

  String get description {
    switch (this) {
      case ViolationKind.counterflow:
        return 'Flags vehicles moving against the legal flow direction inside a zone.';
      case ViolationKind.illegalParking:
        return 'Flags vehicles that dwell inside a restricted zone past a time limit.';
      case ViolationKind.restrictedLane:
        return 'Flags unauthorized vehicle types (e.g., cars) that enter a lane restricted for other vehicles.';
      case ViolationKind.noHelmet:
        return 'Flags motorcycle riders detected without a helmet. No zone needed.';
      case ViolationKind.noPlate:
        return 'Flags vehicles with no visible license plate. No zone needed.';
    }
  }

  IconData get icon {
    switch (this) {
      case ViolationKind.counterflow:
        return Icons.compare_arrows;
      case ViolationKind.illegalParking:
        return Icons.local_parking;
      case ViolationKind.restrictedLane:
        return Icons.directions_bus;
      case ViolationKind.noHelmet:
        return Icons.sports_motorsports;
      case ViolationKind.noPlate:
        return Icons.no_photography;
    }
  }

  /// Key sent to the backend inside `active_violations`.
  String get backendKey {
    switch (this) {
      case ViolationKind.counterflow:
        return 'counterflow';
      case ViolationKind.illegalParking:
        return 'illegal_parking';
      case ViolationKind.restrictedLane:
        return 'restricted_lane';
      case ViolationKind.noHelmet:
        return 'no_helmet';
      case ViolationKind.noPlate:
        return 'no_plate';
    }
  }

  bool get requiresRoi =>
      this == ViolationKind.counterflow || this == ViolationKind.illegalParking || this == ViolationKind.restrictedLane;

  bool get requiresArrow => this == ViolationKind.counterflow;

  bool get requiresTimeLimit => this == ViolationKind.illegalParking;
}

/// A single drawn zone: its own ROI polygon, optional flow arrow, and
/// (for illegal parking) its own dwell time limit. A violation can have
/// multiple zones, each configured one at a time to avoid disorder.
class RoiZone {
  List<Offset> roiPoints;
  List<Offset> arrowPoints;
  int timeLimitSeconds;

  RoiZone({
    List<Offset>? roiPoints,
    List<Offset>? arrowPoints,
    this.timeLimitSeconds = 180,
  }) : roiPoints = roiPoints ?? [],
       arrowPoints = arrowPoints ?? [];

  RoiZone copy() => RoiZone(
    roiPoints: List.from(roiPoints),
    arrowPoints: List.from(arrowPoints),
    timeLimitSeconds: timeLimitSeconds,
  );
}

/// A single configured violation pipeline. Zones are independent per
/// violation type (and from other violations) so drawn areas never clash.
class ViolationConfig {
  final String id;
  ViolationKind kind;
  List<RoiZone> zones;

  ViolationConfig({required this.id, required this.kind, List<RoiZone>? zones})
    : zones = zones ?? [];

  bool isZoneComplete(RoiZone z) =>
      z.roiPoints.length >= 3 &&
      (!kind.requiresArrow || z.arrowPoints.length >= 2);

  bool get isComplete {
    if (!kind.requiresRoi) return true;
    if (zones.isEmpty) return false;
    return zones.every(isZoneComplete);
  }

  ViolationConfig copyWith({List<RoiZone>? zones}) {
    return ViolationConfig(
      id: id,
      kind: kind,
      zones: zones ?? this.zones.map((z) => z.copy()).toList(),
    );
  }
}
