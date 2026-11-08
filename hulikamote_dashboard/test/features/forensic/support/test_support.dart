import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/core/theme/app_theme.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_media.dart';
import 'package:hulikamote_dashboard/features/forensic/data/harvest_labeling.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_gateway.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/forensic_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/harvest_labeling_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/holding_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/harvest_models.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/plate_tools_models.dart';

/// Registers the fonts the SDK ships (Roboto, Material Icons), so widget tests measure and
/// draw text and icons like the real app. The default test font is a block font that is
/// wider than any real one. "Consolas" (plates) is not shipped; Roboto Medium stands in.
Future<void> loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  ByteData? read(String name) {
    final f = File('${dir.path}/$name');
    return f.existsSync() ? ByteData.sublistView(f.readAsBytesSync()) : null;
  }

  final roboto = FontLoader('Roboto');
  for (final name in const ['Regular', 'Medium', 'Bold']) {
    final data = read('Roboto-$name.ttf');
    if (data != null) roboto.addFont(Future.value(data));
  }
  await roboto.load();

  final icons = read('MaterialIcons-Regular.otf');
  if (icons != null) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(icons));
    await l.load();
  }
  final mono = read('Roboto-Medium.ttf');
  if (mono != null) {
    final l = FontLoader('Consolas')..addFont(Future.value(mono));
    await l.load();
  }
}

/// A 1x1 PNG, enough for widgets that only need *an* image.
final Uint8List kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Media that never touches the network.
class FakeMedia extends ForensicMedia {
  FakeMedia([ImageProvider Function(String name)? provider])
      : _provider = provider ?? ((_) => MemoryImage(kTinyPng));

  final ImageProvider Function(String name) _provider;

  @override
  ImageProvider evidence(String name) => _provider(name);

  @override
  ImageProvider thumb(String name, {int width = 240}) => _provider(name);

  @override
  ImageProvider frame(String path) => _provider(path);
}

/// Records what the review workspace asked the backend to do.
class FakeGateway implements ReviewGateway {
  final List<({List<String> ids, ReviewStatus status})> statusCalls = [];
  final List<({String action, Map<String, dynamic> body})> actionCalls = [];
  final List<({String image, String label})> feedbackCalls = [];
  final List<({String uid, String plate, bool revert})> plateCalls = [];
  bool failStatus = false;
  bool failPlate = false;
  List<ForensicTicket> Function(String action, Map<String, dynamic> body)? onAction;

  /// The ticket list the backend would answer with after a plate edit.
  List<ForensicTicket> Function(String uid, String plate, bool revert)? onSetPlate;

  @override
  Future<void> setStatus(List<String> dbIds, ReviewStatus status) async {
    if (failStatus) throw Exception('backend down');
    statusCalls.add((ids: dbIds, status: status));
  }

  @override
  Future<List<ForensicTicket>> ticketAction(String taskId, String action, Map<String, dynamic> body) async {
    actionCalls.add((action: action, body: body));
    return onAction?.call(action, body) ?? const [];
  }

  @override
  Future<List<ForensicTicket>> setPlate(String taskId, String ticketUid, String plate, {bool revert = false}) async {
    if (failPlate) throw Exception('backend down');
    plateCalls.add((uid: ticketUid, plate: plate, revert: revert));
    return onSetPlate?.call(ticketUid, plate, revert) ?? const [];
  }

  @override
  Future<void> sendPlateFeedback({required String imageName, required String label}) async {
    feedbackCalls.add((image: imageName, label: label));
  }

  /// What the backend answers while a running analysis is followed (set it before each look); null = still going, nothing new.
  RunStatus Function(String taskId)? onFollow;
  int follows = 0;
  Object? followError;

  @override
  Future<RunStatus> followStatus(String taskId) async {
    follows++;
    if (followError != null) throw followError!;
    return onFollow?.call(taskId) ?? const RunStatus(status: 'processing', progress: 0);
  }

  /// Holding: what the backend answers (set it before the call) and what was asked.
  final List<({String uid, List<String> frames})> asideCalls = [];
  final List<({String action, Map<String, dynamic> body})> holdingCalls = [];
  List<HoldingBatch> holdingNow = [];
  HoldingResult Function(String? uid, List<String> frames)? onSetAside;
  HoldingResult Function(String action, Map<String, dynamic> body)? onHoldingAction;
  bool failHolding = false;

  @override
  Future<HoldingResult> setAside(String taskId, String ticketUid, List<String> frames) async {
    if (failHolding) throw Exception('backend down');
    asideCalls.add((uid: ticketUid, frames: frames));
    return onSetAside?.call(ticketUid, frames) ?? HoldingResult(tickets: const [], holding: holdingNow);
  }

  @override
  Future<List<HoldingBatch>> loadHolding(String taskId) async {
    if (failHolding) throw Exception('backend down');
    return holdingNow;
  }

  @override
  Future<HoldingResult> holdingAction(String taskId, String action, Map<String, dynamic> body) async {
    if (failHolding) throw Exception('backend down');
    holdingCalls.add((action: action, body: body));
    return onHoldingAction?.call(action, body) ?? HoldingResult(tickets: const [], holding: holdingNow);
  }

  final List<({String uid, List<String> frames})> rereadCalls = [];
  final List<({String image, List<double> box})> boxCalls = [];
  bool failReread = false;

  /// What the backend answers to "Read again" / to a drawn box.
  RereadResult Function(String uid, List<String> frames)? onReread;
  PlateBoxRead Function(String image, List<double> box)? onReadBox;

  @override
  Future<RereadResult> rereadPlate(String taskId, String ticketUid, List<String> frames) async {
    if (failReread) throw Exception('backend down');
    rereadCalls.add((uid: ticketUid, frames: frames));
    return onReread?.call(ticketUid, frames) ?? const RereadResult(tickets: [], checked: 0, found: 0);
  }

  @override
  Future<PlateBoxRead> readPlateBox(String taskId, String image, List<double> box) async {
    boxCalls.add((image: image, box: box));
    return onReadBox?.call(image, box) ?? const PlateBoxRead(text: '');
  }
}

/// One ticket shaped like an entry of report.json.
Map<String, dynamic> ticketJson(
  int i, {
  List<String>? violations,
  String plate = 'unidentified',
  int frames = 12,
  bool withUid = true,
  bool withMeta = true,
  List<Map<String, dynamic>> flags = const [],
  int crops = 0,
  String vclass = 'car',
}) {
  final files = [for (var f = 0; f < frames; f++) 'ev_${i}_$f.jpg'];
  return {
    'track_id': i,
    'violations': violations ?? ['counterflow', 'restricted_lane'],
    'plate_text': plate,
    'evidence_paths': files,
    if (withMeta)
      'evidence_meta': [
        for (var f = 0; f < frames; f++)
          {
            'file': files[f],
            't': i * 2.0 + f * 0.4,
            // the vehicle is largest in the middle of the pass
            'bbox': [100, 100, 100 + 20 * (f < frames / 2 ? f : frames - f), 80 + 10 * (f < frames / 2 ? f : frames - f)],
            'vclass': vclass,
            if (f == 3) 'plate': plate == 'unidentified' ? null : plate,
          },
      ],
    'metadata': {
      'primary_model': '',
      'plate_model': 'plate_specialist.onnx',
      'tracker': 'deepsort',
      'violation_settings': {
        'restricted_lane': {'allowed_classes': ['bus'], 'rois': []},
      },
    },
    'plate_crop_paths': [for (var k = 0; k < crops; k++) 'crop_${i}_$k.jpg'],
    if (crops > 0)
      'crop_results': [
        for (var k = 0; k < crops; k++)
          {
            'image_raw': 'crop_${i}_$k.jpg',
            'image_sr': 'sr_${i}_$k.jpg',
            'raw': k == 0 ? 'KMO5ZZK' : 'KM0522',
            'cleaned': k == 0 ? plate : 'KMO522',
            'confidence': 0.8,
            't': k * 1.0,
          },
      ],
    if (crops > 0) 'vote_tally': {plate: 23.8, 'KMO522': 9.1, 'KHO522K': 4.2},
    if (crops > 0) 'winning_crop': 'crop_${i}_0.jpg',
    if (withUid) 'ticket_uid': 'uid$i',
    'flags': flags,
    'db_ids': ['db${i}a', 'db${i}b'],
  };
}

/// One set of photos waiting in Holding, shaped like an entry of the backend's holding.json (taken out of ticket [from]).
Map<String, dynamic> batchJson(
  String id, {
  String from = 'uid1',
  int fromTrack = 1,
  int frames = 3,
  String plate = 'unidentified',
}) {
  final j = ticketJson(70 + frames, frames: frames, plate: plate, violations: ['counterflow'])
    ..remove('ticket_uid')
    ..remove('db_ids')
    ..remove('flags');
  return {
    ...j,
    'track_id': '$fromTrack (split)',
    'batch_id': id,
    'from_uid': from,
    'from_track': fromTrack,
    'created_at': '2026-11-03T10:00:00+00:00',
  };
}

/// [tickets] with ticket [uid] given the reviewer's [plate], like the backend's set-plate answer.
List<ForensicTicket> withEditedPlate(List<ForensicTicket> tickets, String uid, String plate, {bool revert = false}) {
  return [
    for (final t in tickets)
      if (t.uid != uid)
        t
      else
        ForensicTicket.fromJson({
          ...t.raw,
          if (revert) ...{
            'plate_text': t.plateOcr ?? 'unidentified',
            'plate_manual': false,
            'plate_ocr': null,
          } else ...{
            'plate_text': plate.isEmpty ? 'unidentified' : plate,
            'plate_manual': true,
            'plate_ocr': t.plateManual ? (t.plateOcr ?? 'unidentified') : (t.plateRead ? t.plateText : 'unidentified'),
          },
        }),
  ];
}

/// A believable run: a mix of plates, violations, sizes and flags.
List<ForensicTicket> sampleTickets([int n = 8]) {
  final list = <Map<String, dynamic>>[];
  for (var i = 1; i <= n; i++) {
    list.add(ticketJson(
      i,
      plate: i.isEven ? 'KMO52${i}K' : 'unidentified',
      frames: i == 3 ? 1 : (i == 5 ? 60 : 8 + i),
      violations: switch (i % 3) {
        0 => ['no_helmet', 'overloading'],
        1 => ['counterflow', 'restricted_lane'],
        _ => ['red_light'],
      },
      crops: i.isEven ? 3 : 0,
      vclass: i % 3 == 0 ? 'motorcycle' : (i == 5 ? 'truck' : 'car'),
      flags: i == 2
          ? [
              {'type': 'possible_duplicate', 'other_uid': 'uid4', 'detail': 'one ticket starts where the other ended'}
            ]
          : (i == 6 ? [{'type': 'identity_jump', 'detail': 'the box jumped between two cars'}] : const []),
    ));
  }
  return ForensicTicket.parseList(list);
}

/// Sets a desktop-size surface and wraps [child] in the app theme.
Future<void> pumpScreen(WidgetTester tester, Widget child, {Size size = const Size(1600, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    home: Scaffold(body: child),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

/// A harvest helper that answers from memory: three plate pictures and two cabin pictures to check.
class FakeLabeling implements HarvestLabeling {
  FakeLabeling({
    this.collected = true,
    this.protectedClip = false,
    this.sessionError,
    this.saveError,
    this.hasVideo,
    this.pairError,
    this.pairLoadError,
    this.carError,
    this.fillError,
    bool vehicles = false,
    List<PairItem> pairItems = const [],
    List<CarSummary> carItems = const [],
  }) {
    if (vehicles) {
      pictures['primary_anchor'] = [
        item('v1', boxes: const [HarvestBox(cls: 1, cx: .3, cy: .5, w: .3, h: .4), HarvestBox(cls: 0, cx: .7, cy: .6, w: .2, h: .3)], reason: 'A picture from the clip.'),
        item('v2', reason: 'A picture from the clip.'),
      ];
    }
    pairQueue.addAll(pairItems);
    cars_.addAll(carItems);
  }

  bool collected;
  bool protectedClip;
  bool? hasVideo;
  Object? sessionError;
  Object? saveError;
  Object? pairError; // the answer that fails
  Object? pairLoadError; // the list that fails
  Object? carError; // the check that fails
  Object? fillError; // "the rest are fine" that fails
  int fills = 0;
  final List<CarSummary> cars_ = [];
  final Map<String, List<String>> carPhotos = {}; // uid -> photo names (defaults to p0..p3 when absent)
  final Map<String, List<String>> checkedCars = {}; // uid -> the photos that were marked as another car
  final List<String> carsAsked = [];
  final List<PairItem> pairQueue = [];
  final Map<String, PairAnswer> answeredPairs = {};
  int collects = 0;
  int sessions = 0;
  final List<String?> asked = []; // the analysis each session / queue was asked for
  final Map<String, List<List<num>>> saved = {};
  final List<String> skipped = [];

  static LabelItem item(String id, {List<HarvestBox> boxes = const [], String reason = 'Is there a plate? Box it.'}) => LabelItem(
        id: id,
        state: boxes.isEmpty ? HarvestState.label : HarvestState.check,
        reason: reason,
        boxes: boxes,
        suggested: boxes.isNotEmpty,
        violation: 'no_plate',
        width: 640,
        height: 480,
        task: 't1',
        ticket: 'tk',
      );

  /// Plates: the first picture has a guess, the second has none, the third has two. Cabin: two with a guess.
  final Map<String, List<LabelItem>> pictures = {
    'plate_specialist': [
      item('a1', boxes: const [HarvestBox(cls: 0, cx: .5, cy: .5, w: .4, h: .3)]),
      item('a2'),
      item('a3', boxes: const [HarvestBox(cls: 0, cx: .3, cy: .3, w: .2, h: .2), HarvestBox(cls: 0, cx: .7, cy: .7, w: .2, h: .2)]),
    ],
    'helmet_specialist': const [],
    'cabin_specialist': [
      item('c1', boxes: const [HarvestBox(cls: 2, cx: .5, cy: .5, w: .3, h: .3)]),
      item('c2', boxes: const [HarvestBox(cls: 0, cx: .5, cy: .5, w: .6, h: .3)]),
    ],
  };

  static const classes = {
    'plate_specialist': ['license_plate'],
    'helmet_specialist': ['rider_with_helmet', 'rider_without_helmet'],
    'cabin_specialist': ['clear_window', 'tinted_window', 'seatbelt', 'driver_phone', 'side_mirror'],
    'primary_anchor': ['motorcycle', 'car', 'bus', 'truck', 'person', 'tricycle'],
  };
  static const titles = {'plate_specialist': 'Plate', 'helmet_specialist': 'Helmet', 'cabin_specialist': 'Cabin', 'primary_anchor': 'Vehicles'};

  List<LabelItem> waiting(String model) => [
        for (final i in pictures[model]!)
          if (!saved.containsKey(i.id) && !skipped.contains(i.id)) i,
      ];

  LabelModelInfo info(String model) {
    final all = pictures[model]!;
    final decided = all.where((i) => saved.containsKey(i.id)).length;
    return LabelModelInfo(
      key: model,
      title: titles[model]!,
      classes: classes[model]!,
      help: const {},
      counts: HarvestCounts(check: waiting(model).length, ready: decided, skipped: all.where((i) => skipped.contains(i.id)).length),
    );
  }

  @override
  Future<LabelSession> session(String? taskId) async {
    sessions++;
    asked.add(taskId);
    if (sessionError != null) throw sessionError!;
    return LabelSession(
      task: taskId,
      collected: collected,
      protected: protectedClip,
      collecting: false,
      collectError: null,
      models: [for (final m in pictures.keys) info(m)],
      pairs: PairCounts(
        open: pairQueue.where((p) => !answeredPairs.containsKey(p.id)).length,
        same: answeredPairs.values.where((a) => a == PairAnswer.same).length,
        different: answeredPairs.values.where((a) => a == PairAnswer.different).length,
        skipped: answeredPairs.values.where((a) => a == PairAnswer.notSure).length,
      ),
      cars: taskId == null ? const CarCounts() : _carCounts(),
      hasVideo: taskId == null ? null : hasVideo,
    );
  }

  @override
  Future<LabelSession> collect(String? taskId) async {
    collects++;
    collected = true;
    return session(taskId);
  }

  @override
  Future<LabelQueue> queue(String model, {String? taskId}) async {
    asked.add(taskId);
    return LabelQueue(model: model, classes: classes[model]!, help: const {}, items: waiting(model));
  }

  @override
  Future<PairQueue> pairs({String? taskId}) async {
    asked.add(taskId);
    if (pairLoadError != null) throw pairLoadError!;
    return PairQueue(items: [for (final p in pairQueue) if (!answeredPairs.containsKey(p.id)) p]);
  }

  @override
  Future<void> answerPair(String pairId, PairAnswer answer) async {
    if (pairError != null) throw pairError!;
    answeredPairs[pairId] = answer;
  }

  @override
  ImageProvider pairImage(String pairId, String side) => MemoryImage(kTinyPng);

  CarState _stateOf(CarSummary c) => !checkedCars.containsKey(c.uid)
      ? c.state
      : (checkedCars[c.uid]!.isEmpty ? CarState.checked : CarState.split);

  CarCounts _carCounts() => CarCounts(
        open: cars_.where((c) => _stateOf(c) == CarState.open).length,
        checked: cars_.where((c) => _stateOf(c) == CarState.checked).length,
        split: cars_.where((c) => _stateOf(c) == CarState.split).length,
      );

  @override
  Future<CarList> cars(String taskId) async {
    carsAsked.add(taskId);
    final items = [
      for (final c in cars_) CarSummary(uid: c.uid, track: c.track, photos: c.photos, first: c.first, state: _stateOf(c)),
    ];
    return CarList(
      evidenceDir: 'evidence',
      items: items,
      counts: CarCounts(
        open: items.where((c) => c.state == CarState.open).length,
        checked: items.where((c) => c.state == CarState.checked).length,
        split: items.where((c) => c.state == CarState.split).length,
      ),
    );
  }

  @override
  Future<CarDetail> car(String taskId, String uid) async {
    final summary = cars_.firstWhere((c) => c.uid == uid);
    return CarDetail(
      uid: uid,
      track: summary.track,
      evidenceDir: 'evidence',
      photos: carPhotos[uid] ?? [for (var i = 0; i < summary.photos; i++) '${uid}_$i.jpg'],
      marked: {...?checkedCars[uid]},
    );
  }

  @override
  Future<void> checkCar(String taskId, String uid, List<String> different) async {
    if (carError != null) throw carError!;
    checkedCars[uid] = different;
  }

  @override
  Future<int> fillCars(String taskId) async {
    if (fillError != null) throw fillError!;
    fills++;
    var n = 0;
    for (final c in cars_) {
      if (_stateOf(c) == CarState.open) {
        checkedCars[c.uid] = [];
        n++;
      }
    }
    return n;
  }

  @override
  ImageProvider carPhoto(String evidenceDir, String file, {int? width}) => MemoryImage(kTinyPng);

  @override
  ImageProvider image(String model, String id, {int? width}) => MemoryImage(kTinyPng);

  @override
  Future<void> save(String itemId, List<HarvestBox> boxes) async {
    if (saveError != null) throw saveError!;
    saved[itemId] = [for (final b in boxes) [b.cls, b.cx, b.cy, b.w, b.h]];
  }

  @override
  Future<void> skip(String itemId) async {
    if (saveError != null) throw saveError!;
    skipped.add(itemId);
  }
}
