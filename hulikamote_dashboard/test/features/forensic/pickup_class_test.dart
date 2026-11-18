import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/lane_signs.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/violation_catalog.dart';

void main() {
  test('a pickup is offered as a vehicle type, but a truck ban still starts with trucks only', () {
    expect(ViolationCatalog.vehicleTypes, contains('pickup'));
    expect(AnalysisDraft.defaultConfig('truck_ban')['banned_classes'], ['truck']);
    expect(AnalysisDraft.defaultConfig('illegal_loading')['banned_classes'], isNot(contains('pickup')));
    expect(AnalysisDraft.defaultConfig('sidewalk_driving')['banned_classes'], contains('pickup'));
  });

  test('a lane sign knows the pickup as its own type', () {
    expect(LaneSigns.vehicleTypes, contains('pickup'));
    expect(LaneSigns.of('no_trucks')!.allowed, contains('pickup')); // a no-trucks sign does not stop a pickup
    expect(LaneSigns.of('bus_only')!.allowed, isNot(contains('pickup')));
  });
}
