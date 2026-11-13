import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/review_controller.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/violation_catalog.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/zone_geometry.dart';

import 'support/test_support.dart';

void main() {
  group('ForensicTicket.fromJson', () {
    test('reads the reviewer edit and what the system read before it', () {
      final edited = ForensicTicket.fromJson({
        ...ticketJson(1, plate: 'NEW111'),
        'plate_manual': true,
        'plate_ocr': 'OLD222',
      });
      expect(edited.plateManual, isTrue);
      expect(edited.plateOcr, 'OLD222');
      final none = ForensicTicket.fromJson({
        ...ticketJson(2, plate: 'NEW111'),
        'plate_manual': true,
        'plate_ocr': 'unidentified',
      });
      expect(none.plateOcr, isNull);
      expect(ForensicTicket.fromJson(ticketJson(3)).plateManual, isFalse);
    });

    test('reads the current report format', () {
      final t = ForensicTicket.fromJson(ticketJson(7, plate: 'KMO522K', frames: 10, crops: 3));
      expect(t.uid, 'uid7');
      expect(t.hasUid, isTrue);
      expect(t.trackId, 7);
      expect(t.plateRead, isTrue);
      expect(t.frameCount, 10);
      expect(t.crops, hasLength(3));
      expect(t.crops.first.hasRead, isTrue);
      expect(t.winningCropFile, 'crop_7_0.jpg');
      expect(t.bestCrop!.file, 'crop_7_0.jpg');
      expect(t.candidates.first.key, 'KMO522K'); // most votes first
      expect(t.span!.start, 14.0);
    });

    test('older reports without uid or evidence_meta still load', () {
      final t = ForensicTicket.fromJson(ticketJson(3, withUid: false, withMeta: false, frames: 4));
      expect(t.uid, 't3');
      expect(t.hasUid, isFalse);
      expect(t.frameCount, 4);
      expect(t.span, isNull);
      expect(t.frames.first.t, isNull);
    });

    test('"unidentified" and friends are unread plates', () {
      for (final p in ['unidentified', 'no_plate_found', '', 'UNIDENTIFIED']) {
        expect(ForensicTicket.fromJson(ticketJson(1, plate: p)).plateRead, isFalse, reason: p);
      }
    });

    test('the best view is the photo where the vehicle is largest', () {
      final t = ForensicTicket.fromJson(ticketJson(1, frames: 10));
      // ticketJson makes the vehicle grow until the middle of the pass
      expect(t.heroIndex, 5);
      expect(t.hero!.file, 'ev_1_5.jpg');
    });

    test('flags become typed with their own wording', () {
      final t = ForensicTicket.fromJson(ticketJson(2, flags: [
        {'type': 'possible_duplicate', 'other_uid': 'uid4', 'detail': 'x'},
        {'type': 'identity_jump', 'detail': 'y'},
      ]));
      expect(t.isFlagged, isTrue);
      expect(t.flags.first.isDuplicate, isTrue);
      expect(t.flags.first.otherUid, 'uid4');
      expect(t.flags.last.title, contains('tracker'));
    });
  });

  test('formatVideoTime', () {
    expect(formatVideoTime(4.2), '0:04.2');
    expect(formatVideoTime(75.5), '1:15.5');
    expect(formatVideoTime(null), '—');
  });

  group('ReviewController', () {
    ReviewController make(FakeGateway g, {int n = 6, Map<String, ReviewStatus>? statuses}) =>
        ReviewController(gateway: g, taskId: 'task', tickets: sampleTickets(n), statuses: statuses);

    test('opens the first ticket that needs a look: flagged ones first', () {
      final c = make(FakeGateway());
      expect(c.selected!.isFlagged, isTrue);
      expect(c.total, 6);
      expect(c.reviewedCount, 0);
    });

    test('filters by status, flag, violation and search', () {
      final c = make(FakeGateway());
      expect(c.visible, hasLength(6));
      c.setFilter(QueueFilter.flagged);
      expect(c.visible.every((t) => t.isFlagged), isTrue);
      c.clearFilters();
      c.toggleViolationFilter('red_light');
      expect(c.visible.every((t) => t.violations.contains('red_light')), isTrue);
      c.clearFilters();
      c.setQuery('KMO522K'); // ticket 2's plate: KMO52<2>K
      expect(c.visible.map((t) => t.trackId), [2]);
      expect(c.hasActiveFilters, isTrue);
      c.clearFilters();
      expect(c.hasActiveFilters, isFalse);
    });

    test('sorts', () {
      final c = make(FakeGateway());
      c.setSort(QueueSort.mostFrames);
      final counts = c.visible.map((t) => t.frameCount).toList();
      expect(counts, [...counts]..sort((a, b) => b.compareTo(a)));
      c.setSort(QueueSort.trackId);
      expect(c.visible.map((t) => t.trackId), [1, 2, 3, 4, 5, 6]);
    });

    test('selection moves through the visible queue and stops at the ends', () {
      final c = make(FakeGateway());
      c.setSort(QueueSort.trackId);
      c.select(c.visible.first.uid);
      c.selectRelative(-1);
      expect(c.selected!.trackId, 1);
      c.selectRelative(2);
      expect(c.selected!.trackId, 3);
      c.selectRelative(99);
      expect(c.selected!.trackId, 6);
    });

    test('opening a ticket starts on its best photo; stepping stays in range', () {
      final c = make(FakeGateway());
      c.select(c.all.firstWhere((t) => t.trackId == 5).uid); // 60 photos
      expect(c.frameIndex, c.selected!.heroIndex);
      c.setFrame(-5);
      expect(c.frameIndex, 0);
      c.setFrame(1 << 20);
      expect(c.frameIndex, 59);
      c.stepFrame(1);
      expect(c.frameIndex, 59);
    });

    test('a decision is sent for every violation row and counted', () async {
      final g = FakeGateway();
      final c = make(g);
      final t = c.selected!;
      expect(await c.decide(t.uid, ReviewStatus.confirmed), isTrue);
      expect(g.statusCalls.single.ids, t.dbIds);
      expect(g.statusCalls.single.status, ReviewStatus.confirmed);
      expect(c.statusOf(t), ReviewStatus.confirmed);
      expect(c.reviewedCount, 1);
      expect(c.confirmedCount, 1);
    });

    test('after a decision the next ticket still waiting opens', () async {
      final c = make(FakeGateway());
      final first = c.selected!;
      await c.decide(first.uid, ReviewStatus.rejected);
      expect(c.selected!.uid, isNot(first.uid));
      expect(c.statusOf(c.selected!), ReviewStatus.pending);
    });

    test('a failed save rolls the decision back and reports it', () async {
      final g = FakeGateway()..failStatus = true;
      final c = make(g);
      final t = c.selected!;
      expect(await c.decide(t.uid, ReviewStatus.confirmed), isFalse);
      expect(c.statusOf(t), ReviewStatus.pending);
      expect(c.error, contains('Could not save'));
      c.clearError();
      expect(c.error, isNull);
    });

    test('undo restores the previous status', () async {
      final g = FakeGateway();
      final c = make(g);
      final t = c.selected!;
      await c.decide(t.uid, ReviewStatus.confirmed);
      expect(c.canUndo, isTrue);
      expect(await c.undo(), isTrue);
      expect(c.statusOf(t), ReviewStatus.pending);
      expect(g.statusCalls.last.status, ReviewStatus.pending);
      expect(c.canUndo, isFalse);
    });

    test('batch: every ticked ticket gets the decision, then the ticks clear', () async {
      final g = FakeGateway();
      final c = make(g);
      c.toggleChecked(c.all[0].uid);
      c.toggleChecked(c.all[1].uid);
      expect(await c.decideChecked(ReviewStatus.rejected), isTrue);
      expect(g.statusCalls, hasLength(2));
      expect(c.rejectedCount, 2);
      expect(c.checked, isEmpty);
    });

    test('earlier decisions loaded from the backend are respected', () {
      final tickets = sampleTickets(4);
      final c = ReviewController(
        gateway: FakeGateway(),
        taskId: 't',
        tickets: tickets,
        statuses: {tickets[1].uid: ReviewStatus.confirmed},
      );
      expect(c.reviewedCount, 1);
      c.setFilter(QueueFilter.toReview);
      expect(c.visible.any((t) => t.uid == tickets[1].uid), isFalse);
    });

    test('merge keeps the reviewer\'s place and drops statuses of tickets that disappeared', () async {
      final g = FakeGateway();
      final c = make(g);
      final keep = c.all[1];
      final drop = c.all[2];
      await c.decide(drop.uid, ReviewStatus.confirmed);
      c.select(keep.uid);
      g.onAction = (action, body) => [for (final t in c.all) if (t.uid != drop.uid) t];
      expect(await c.ticketAction('merge', {'keep_uid': keep.uid, 'merge_uid': drop.uid}, thenSelect: keep.uid), isTrue);
      expect(c.total, 5);
      expect(c.selected!.uid, keep.uid);
      expect(c.reviewedCount, 0);
      expect(g.actionCalls.single.body['task_id'], 'task');
    });

    test('a saved plate replaces the ticket plate and keeps decisions and place', () async {
      final g = FakeGateway();
      final c = make(g);
      final t = c.all.firstWhere((x) => !x.plateRead);
      c.select(t.uid);
      await c.decide(t.uid, ReviewStatus.confirmed);
      c.select(t.uid);
      c.setFrame(2);
      g.onSetPlate = (uid, plate, revert) => withEditedPlate(c.all, uid, plate, revert: revert);

      final ok = await c.setPlate(t, ' abc 123 ');
      expect(ok, isTrue);
      expect(g.plateCalls.single, (uid: t.uid, plate: 'abc 123', revert: false));
      final now = c.all.firstWhere((x) => x.uid == t.uid);
      expect(now.plateText, 'abc 123');
      expect(now.plateManual, isTrue);
      expect(now.plateOcr, isNull); // the system read nothing
      expect(c.selectedUid, t.uid);
      expect(c.frameIndex, 2); // the open photo did not jump
      expect(c.statusOf(now), ReviewStatus.confirmed);
      expect(c.error, isNull);
    });

    test('a plate that could not be saved leaves the ticket as it was and says why', () async {
      final g = FakeGateway()..failPlate = true;
      final c = make(g);
      final t = c.all.first;
      expect(await c.setPlate(t, 'XYZ 999'), isFalse);
      expect(c.all.first.plateText, t.plateText);
      expect(c.error, contains('Could not save the plate'));
      expect(c.busy, isFalse);
    });

    test('going back to the system read sends revert', () async {
      final g = FakeGateway();
      final c = make(g);
      final t = c.all.firstWhere((x) => x.plateRead);
      g.onSetPlate = (uid, plate, revert) => withEditedPlate(c.all, uid, plate, revert: revert);
      await c.setPlate(t, 'NEW 111');
      final edited = c.all.firstWhere((x) => x.uid == t.uid);
      expect(edited.plateOcr, t.plateText);
      await c.setPlate(edited, '', revert: true);
      expect(g.plateCalls.last.revert, isTrue);
      final back = c.all.firstWhere((x) => x.uid == t.uid);
      expect(back.plateText, t.plateText);
      expect(back.plateManual, isFalse);
    });

    test('plate feedback goes out with the chosen crop and is remembered', () async {
      final g = FakeGateway();
      final c = make(g);
      final t = c.all.firstWhere((x) => x.crops.isNotEmpty);
      c.select(t.uid);
      c.chooseCrop(t.uid, t.crops[1].file);
      expect(c.chosenCrop(t)!.file, t.crops[1].file);
      await c.sendPlateFeedback(t, c.chosenCrop(t)!, 'abc123');
      expect(g.feedbackCalls.single.label, 'abc123');
      expect(g.feedbackCalls.single.image, t.crops[1].enhanced);
      expect(c.plateFeedbackFor(t.uid), 'ABC123');
    });
  });

  group('AnalysisDraft', () {
    test('sends the same config keys and defaults the backend has always received', () {
      final d = AnalysisDraft();
      d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg', fps: 25, frames: 500);
      d.toggle('counterflow');
      d.toggle('overloading');
      final cfg = d.buildConfig(activePlateModel: 'plate_x.onnx');
      expect(cfg.keys, containsAll([
        'active_violations', 'tracker', 'plate_model', 'plate_method', 'plate_format', 'ocr_engine',
        'enhancement', 'primary_model', 'use_sahi', 'flag_sensitivity', 'evidence_gap', 'keep_input_video',
        'per_violation_configs',
      ]));
      expect(cfg['active_violations'], ['counterflow', 'overloading']);
      expect(cfg['plate_model'], 'plate_x.onnx'); // "active model" resolved
      final per = cfg['per_violation_configs'] as Map;
      expect(per.keys, containsAll(['counterflow', 'overloading']));
      expect(per['counterflow']['time_limit'], 180.0);
      expect(per['overloading']['max_riders'], 2);
      expect(per['counterflow']['allowed_classes'], ['bus']);
    });

    test('counterflow shows its flow arrows by default and the reversed-flow test starts off', () {
      final d = AnalysisDraft();
      d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg', fps: 25, frames: 500);
      d.toggle('counterflow');
      var per = d.buildConfig(activePlateModel: 'p.onnx')['per_violation_configs'] as Map;
      expect(per['counterflow']['show_flow'], true);
      expect(per['counterflow']['invert_flow'], false);
      d.config('counterflow')['invert_flow'] = true;
      d.config('counterflow')['show_flow'] = false;
      per = d.buildConfig(activePlateModel: 'p.onnx')['per_violation_configs'] as Map;
      expect(per['counterflow']['invert_flow'], true);
      expect(per['counterflow']['show_flow'], false);
    });

    test('the privacy blur is on unless the operator switches it off for a run', () {
      final d = AnalysisDraft();
      d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg', fps: 25, frames: 500);
      d.toggle('counterflow');
      expect(d.buildConfig(activePlateModel: 'p.onnx')['blur_privacy'], true);
      d.settings.blurPrivacy = false;
      expect(d.buildConfig(activePlateModel: 'p.onnx')['blur_privacy'], false);
    });

    test('the wizard offers all 25 violations, each with the right kind of zone', () {
      expect(ViolationCatalog.all.length, 25);
      expect(ViolationCatalog.all.map((v) => v.key).toSet().length, 25);
      expect(ViolationCatalog.selectable.length, 25);
      for (final key in [
        'illegal_u_turn', 'blocking_intersection', 'crossing_solid_line',
        'illegal_loading', 'truck_ban', 'tricycle_on_highway', 'sidewalk_driving', 'double_parking',
      ]) {
        expect(ViolationCatalog.of(key).needsZone, isTrue, reason: key);
      }
      for (final key in ['pickup_passengers', 'riding_outside_vehicle']) {
        expect(ViolationCatalog.of(key).needsZone, isFalse, reason: key); // judged from what is on screen
      }
      expect(ViolationCatalog.arrowViolations, contains('crossing_solid_line'));
      expect(ViolationCatalog.lineViolations, {'red_light', 'crossing_solid_line'});
      expect(AnalysisDraft.defaultConfig('blocking_intersection')['time_limit'], 5.0);
    });

    test('the five Philippine road rules start with the same defaults as the backend', () {
      expect(AnalysisDraft.defaultConfig('illegal_loading')['time_limit'], 8.0);
      expect(AnalysisDraft.defaultConfig('double_parking')['time_limit'], 8.0);
      expect(AnalysisDraft.defaultConfig('illegal_loading')['banned_classes'], ['bus', 'jeepney', 'tricycle', 'truck']);
      expect(AnalysisDraft.defaultConfig('truck_ban')['banned_classes'], ['truck']);
      expect(AnalysisDraft.defaultConfig('tricycle_on_highway')['banned_classes'], ['tricycle']);
      expect(AnalysisDraft.defaultConfig('sidewalk_driving')['banned_classes'],
          ['car', 'motorcycle', 'bus', 'truck', 'tricycle']);
      expect(AnalysisDraft.defaultConfig('counterflow')['banned_classes'], isEmpty); // the others are untouched
      expect(AnalysisDraft.defaultConfig('counterflow')['time_limit'], 180.0);
    });

    test('violations with no zone start straight away, and a solid line needs no drawing either', () {
      final d = AnalysisDraft();
      d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
      d.toggle('pickup_passengers');
      d.toggle('riding_outside_vehicle');
      expect(d.canStart, isTrue);
      d.toggle('crossing_solid_line');
      expect(d.missingZones, isEmpty); // the painted solid lines are found when the analysis starts
      expect(d.canStart, isTrue);
      d.config('crossing_solid_line')['auto_lines'] = false;
      expect(d.missingZones, ['crossing_solid_line']); // with the search turned off a line has to be drawn
      d.zones('crossing_solid_line').add({
        'line': [[0.0, 0.0], [1.0, 1.0]],
      });
      expect(d.missingZones, isEmpty);
    });

    test('defaults differ per violation like before', () {
      expect(AnalysisDraft.defaultConfig('pedestrian_lane')['time_limit'], 3.0);
      expect(AnalysisDraft.defaultConfig('disregarding_signs')['time_limit'], 5.0);
    });

    test('a violation that needs a zone blocks starting until one is saved', () {
      final d = AnalysisDraft();
      d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
      d.toggle('pedestrian_lane');
      expect(d.missingZones, ['pedestrian_lane']);
      expect(d.canStart, isFalse);
      d.zones('pedestrian_lane').add({'polygon': <List<double>>[]});
      expect(d.missingZones, isEmpty);
      expect(d.canStart, isTrue);
      d.toggle('no_plate'); // needs no zone
      expect(d.canStart, isTrue);
    });

    test('counterflow needs no zone and the flow is learned on its own, but only when nothing is drawn', () {
      final d = AnalysisDraft();
      d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
      d.toggle('counterflow');
      d.toggle('pedestrian_lane');
      expect(d.learnsFlow, isTrue);
      expect(d.buildConfig()['flow_mode'], 'auto');
      expect(d.missingZones, ['pedestrian_lane']); // other rules still need their zone
      d.toggle('pedestrian_lane');
      expect(d.canStart, isTrue);
      d.zones('counterflow').add({'polygon': <List<double>>[]}); // a drawn zone (and its arrow) is used instead
      expect(d.learnsFlow, isFalse);
      expect(d.buildConfig()['flow_mode'], 'zones');
    });

    test('the flow is learned only for the rules that use it', () {
      final d = AnalysisDraft();
      d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
      for (final k in ['truck_ban', 'swerving', 'illegal_turn', 'illegal_u_turn', 'signal_light', 'tricycle_on_highway', 'double_parking']) {
        d.toggle(k);
      }
      expect(d.learnsFlow, isFalse);
      expect(d.buildConfig()['flow_mode'], 'zones');
      d.toggle('illegal_parking'); // a stopped car counts only while traffic drives past
      expect(d.learnsFlow, isTrue);
      expect(AnalysisDraft.wholeFrameKeys.containsAll(AnalysisDraft.flowKeys), isTrue);
    });

    test('every rule that needs no drawing starts without a zone, and its settings still travel in the payload', () {
      final d = AnalysisDraft();
      d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
      for (final k in AnalysisDraft.wholeFrameKeys) {
        d.toggle(k);
      }
      expect(d.missingZones, isEmpty);
      expect(d.canStart, isTrue);
      final per = d.buildConfig()['per_violation_configs'] as Map;
      expect(per['illegal_turn']['banned_turns'], ['left']); // which turns are banned: the enforcer's choice
      expect(per['truck_ban']['banned_classes'], ['truck']);
      expect(per['illegal_parking']['time_limit'], isNotNull);
    });

    test('rules that cannot work without a drawing are not offered as whole-picture rules', () {
      for (final k in ['pedestrian_lane', 'red_light', 'blocking_intersection',
        'sidewalk_driving', 'disregarding_signs', 'crossing_solid_line']) {
        expect(AnalysisDraft.wholeFrameKeys.contains(k), isFalse, reason: k);
      }
    });

    test('choosing a new video forgets the old choices', () {
      final d = AnalysisDraft();
      d.setVideo(path: 'a.mp4', name: 'a.mp4', frame: '/f.jpg');
      d.toggle('counterflow');
      d.zones('counterflow').add({'polygon': <List<double>>[]});
      d.setVideo(path: 'b.mp4', name: 'b.mp4', frame: '/g.jpg');
      expect(d.selection, isEmpty);
      expect(d.zones('counterflow'), isEmpty);
    });

    test('selection follows the catalog order, not the click order', () {
      final d = AnalysisDraft();
      d.toggle('no_plate');
      d.toggle('counterflow');
      expect(d.selection, ['counterflow', 'no_plate']);
    });
  });

  group('ZoneGeometry', () {
    test('canvas coordinates round-trip through the 1920x1080 reference space', () {
      const pts = [Offset(0.5, 0.5), Offset(0.25, 0.75)];
      final ref = ZoneGeometry.toReference(pts);
      expect(ref.first, [960.0, 540.0]);
      final back = ZoneGeometry.fromReference(ref);
      expect(back[1].dx, closeTo(0.25, 1e-9));
      expect(back[1].dy, closeTo(0.75, 1e-9));
    });

    test('same numbers as the old 960x540 canvas (x2)', () {
      // the old screen multiplied canvas pixels by 2.0; 480,270 of 960x540 is the centre
      expect(ZoneGeometry.toReference([const Offset(480 / 960, 270 / 540)]).first, [960.0, 540.0]);
    });

    test('direction vector is in reference pixels', () {
      final v = ZoneGeometry.vectorOf(const Offset(0.5, 0.9), const Offset(0.5, 0.4));
      expect(v['x_dir'], 0);
      expect(v['y_dir'], closeTo(-540, 1e-9));
    });

    test('hit finds the nearest handle within the radius', () {
      const size = Size(1000, 500);
      final pts = [const Offset(0.1, 0.1), const Offset(0.5, 0.5)];
      expect(ZoneGeometry.hit(pts, const Offset(505, 252), size), 1);
      expect(ZoneGeometry.hit(pts, const Offset(700, 300), size), isNull);
    });
  });

  test('catalog: every selectable violation has a label, group and unique key', () {
    final keys = ViolationCatalog.selectable.map((v) => v.key).toList();
    expect(keys.toSet(), hasLength(keys.length));
    expect(keys, contains('red_light'));
    expect(ViolationCatalog.of('something_new').label, 'Something New'); // unknown keys stay readable
  });
}
