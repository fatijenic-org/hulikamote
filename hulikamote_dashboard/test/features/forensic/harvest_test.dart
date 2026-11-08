import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/data/harvest_source.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/harvest_models.dart';

import 'support/test_support.dart';

/// The shape harvest_tool/gallery.py writes.
Map<String, dynamic> sampleGallery() {
  Map<String, dynamic> item(
    int n,
    String state, {
    String why = "'No plate' ticket",
    String? violation = 'no_plate',
    String source = 'ticket',
    List<List<num>> boxes = const [],
    bool suggested = false,
  }) =>
      {
        'id': 'id${n.toString().padLeft(14, '0')}',
        'image': 'plate_specialist/images/id$n.jpg',
        'state': state,
        'source': source,
        'why': why,
        'reason': 'Is a plate visible for item $n? Draw a box around it, or press N = nothing here.',
        'violation': violation,
        'decision': 'pending',
        'suggested': suggested,
        'boxes': boxes,
        'width': 120,
        'height': 90,
        'group': 'g$n',
        'task': '0a51c09e-62c1-4f67-9a76-be7248c878fd',
        'ticket': 'tk$n',
        'created': 1791854860.0 + n,
        'decided': state == 'ready' ? 1791860000.0 : null,
        'accepted': null,
        'dataset_name': null,
      };

  final items = [
    item(1, 'check', boxes: [[0, .5, .5, .3, .2]], suggested: true),
    item(2, 'check', why: 'Plate never read (counterflow ticket)', violation: 'counterflow', suggested: true),
    item(3, 'check', why: 'Plate never read (counterflow ticket)', violation: 'counterflow'),
    item(4, 'label', why: 'Plate never read (red light ticket)', violation: 'red_light'),
    item(5, 'label', why: 'Cut from a plate photo', violation: null, source: 'plate_photo_cut'),
    item(6, 'ready', boxes: [[0, .4, .6, .2, .1]]),
    item(7, 'skipped', why: 'Plate was read: check the box', violation: null),
  ];
  return {
    'schema': 1,
    'generated': DateTime.now().subtract(const Duration(minutes: 3)).millisecondsSinceEpoch / 1000,
    'lab': 'C:/lab',
    'inbox': 'C:/lab/harvest_inbox',
    'protected': 2,
    'categories': [
      {
        'key': 'plate_specialist',
        'kind': 'detector',
        'title': 'Plate finder',
        'does': 'finds the license plate on a vehicle',
        'used_for': 'Teaches the plate finder to spot number plates it missed.',
        'fed_by': ['Vehicles from tickets where no plate was found', 'Plate photos you already have'],
        'your_job': 'Plate visible? Draw a box around it. No plate? Press N.',
        'violations': ['no_plate'],
        'classes': [
          {'name': 'license_plate', 'help': 'The number plate. Draw the box tight around it.'},
        ],
        'model_file': 'plate_specialist_train2.onnx',
        'training': false,
        'dataset_images': 7116,
        'counts': {'check': 3, 'label': 2, 'ready': 1, 'skipped': 1, 'accepted': 0, 'needs_eyes': 5, 'total': 7},
        'next': '5 pictures need your eyes.',
        'sources': [
          {'key': 'ticket', 'label': 'Vehicles from your forensic tickets', 'n': 6},
          {'key': 'plate_photo_cut', 'label': 'Cut from plate photos you already have', 'n': 1},
        ],
        'violations_seen': [
          {'violation': 'counterflow', 'n': 2},
          {'violation': 'no_plate', 'n': 2},
        ],
        'listed': 7,
        'items': items,
      },
      {
        'key': 'helmet_specialist',
        'kind': 'detector',
        'title': 'Helmet check',
        'does': 'tells riders with a helmet from riders without',
        'used_for': 'Teaches the helmet check what riders with and without a helmet look like.',
        'fed_by': ["Vehicles from 'no helmet' tickets"],
        'your_job': 'Box each rider: with a helmet, or without.',
        'violations': ['no_helmet'],
        'classes': [
          {'name': 'rider_with_helmet', 'help': 'A rider wearing a helmet.'},
          {'name': 'rider_without_helmet', 'help': 'A rider with a bare head.'},
        ],
        'model_file': null,
        'training': null,
        'dataset_images': 0,
        'counts': {'check': 0, 'label': 0, 'ready': 0, 'skipped': 0, 'accepted': 0, 'needs_eyes': 0, 'total': 0},
        'next': 'Nothing waiting. Analyze more clips, then press Collect.',
        'sources': <Map>[],
        'violations_seen': <Map>[],
        'listed': 0,
        'items': <Map>[],
      },
      {
        'key': 'plate_ocr',
        'kind': 'automatic',
        'title': 'Plate text reader',
        'does': 'reads the letters and digits of a plate',
        'used_for': 'Teaches the reader to read the characters of a plate.',
        'fed_by': ["Corrections typed under 'Teach the OCR' in the review screen"],
        'your_job': 'Nothing to check here. It grows each time you teach the OCR.',
        'how': 'Pop Quiz corrections in the review screens',
        'count': 42,
        'need': 500,
        'unit': 'pictures',
        'samples': [
          {'path': 'datasets/plate_ocr/images/train/AK64DMV_1790380231712.jpg', 'label': 'AK64DMV', 'when': 1790380231.7},
          {'path': 'datasets/plate_ocr/images/train/AP05JEO_1790380345838.jpg', 'label': 'AP05JEO', 'when': 1790380345.8},
        ],
        'groups': <Map>[],
        'facts': <Map>[],
      },
      {
        'key': 'reid',
        'kind': 'automatic',
        'title': 'Car matcher',
        'does': 'tells whether two photos show the same car',
        'used_for': 'Teaches the tracker which photos belong to one car.',
        'fed_by': ["Merge ('same car') and Separate decisions in the review screen"],
        'your_job': 'Nothing to check here.',
        'how': 'merge / separate decisions in the review screens',
        'count': 4,
        'need': 5,
        'unit': 'cars with 2+ photos',
        'samples': <Map>[],
        'groups': [
          {
            'id': '0a51c09e/0a51c09e_26e6',
            'n': 18,
            'photos': ['datasets/reid/images/t/c/1.jpg', 'datasets/reid/images/t/c/2.jpg'],
          },
        ],
        'facts': [
          {'label': "'Same car' decisions", 'value': 3},
          {'label': "'Different car' decisions", 'value': 1},
        ],
      },
    ],
  };
}

class FakeHarvest implements HarvestSource {
  FakeHarvest({Map<String, dynamic>? json, this.loadError, this.rebuildProblem}) : json = json ?? sampleGallery();

  Map<String, dynamic>? json;
  HarvestException? loadError;
  String? rebuildProblem;
  int loads = 0, rebuilds = 0;

  @override
  Future<HarvestGallery?> load() async {
    loads++;
    final e = loadError;
    if (e != null) throw e;
    final j = json;
    return j == null ? null : HarvestGallery.fromJson(j);
  }

  @override
  Future<String?> rebuild() async {
    rebuilds++;
    return rebuildProblem;
  }

  @override
  ImageProvider inboxImage(String relative, {int? width}) => MemoryImage(kTinyPng);

  @override
  ImageProvider labImage(String relative, {int? width}) => MemoryImage(kTinyPng);
}

void main() {
  setUpAll(loadRoboto);

  group('models', () {
    test('the snapshot parses into groups, counts and pictures', () {
      final g = HarvestGallery.fromJson(sampleGallery());
      expect(g.categories.map((c) => c.key), ['plate_specialist', 'helmet_specialist', 'plate_ocr', 'reid']);
      expect(g.detectors, hasLength(2));
      expect((g.total, g.needEyes, g.ready, g.added), (7, 5, 1, 0));
      expect(g.protectedClips, 2);

      final plate = g.byKey('plate_specialist')!;
      expect(plate.isDetector, isTrue);
      expect(plate.counts.needsEyes, 5);
      expect(plate.items.first.state, HarvestState.check);
      expect(plate.items.first.boxes.single.cx, 0.5);
      expect(plate.items[4].source, 'plate_photo_cut');
      expect(plate.classes.single.name, 'license_plate');
      expect(plate.training, isFalse);

      final ocr = g.byKey('plate_ocr')!;
      expect(ocr.isDetector, isFalse);
      expect(ocr.progress, closeTo(42 / 500, 1e-9));
      expect(ocr.samples.first.label, 'AK64DMV');
      expect(g.byKey('reid')!.groups.single.photos, hasLength(2));
      expect(g.byKey('helmet_specialist')!.training, isNull);
    });

    test('missing or odd fields do not break the parse', () {
      final g = HarvestGallery.fromJson({
        'categories': [
          {'key': 'x', 'items': [{'id': 'a', 'image': 'x/a.jpg', 'state': 'weird', 'boxes': [[0, 1]]}]},
        ],
      });
      final c = g.categories.single;
      expect(c.items.single.state, HarvestState.check); // unknown state = waiting for a look
      expect(c.items.single.boxes, isEmpty);
      expect(c.counts.total, 0);
      expect(g.generated, isNull);
    });
  });

  group('LocalHarvestSource', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('harvest_src_'));
    tearDown(() => root.deleteSync(recursive: true));

    Directory makeLab() {
      final lab = Directory('${root.path}/repo/training_lab')..createSync(recursive: true);
      File('${lab.path}/harvest.py').writeAsStringSync('# stub');
      Directory('${lab.path}/harvest_tool').createSync();
      Directory('${lab.path}/harvest_inbox').createSync();
      return lab;
    }

    test('finds the lab by walking up from where the app runs', () {
      final lab = makeLab();
      final deep = Directory('${root.path}/repo/hulikamote_dashboard/build/windows')..createSync(recursive: true);
      final source = LocalHarvestSource(searchFrom: [deep.path]);
      expect(source.findLab(), lab.path.replaceAll('\\', '/'));
    });

    test('reads the snapshot; null until the tool has written one', () async {
      final lab = makeLab();
      final source = LocalHarvestSource(labDir: lab.path);
      expect(await source.load(), isNull);
      File('${lab.path}/harvest_inbox/gallery.json').writeAsStringSync(jsonEncode(sampleGallery()));
      final g = await source.load();
      expect(g!.total, 7);
    });

    test('says so when the lab cannot be found or the snapshot is damaged', () async {
      final empty = Directory('${root.path}/nothing')..createSync();
      await expectLater(
        LocalHarvestSource(searchFrom: [empty.path]).load(),
        throwsA(isA<HarvestException>().having((e) => e.message, 'message', contains('training_lab'))),
      );
      final lab = makeLab();
      File('${lab.path}/harvest_inbox/gallery.json').writeAsStringSync('{ not json');
      await expectLater(LocalHarvestSource(labDir: lab.path).load(), throwsA(isA<HarvestException>()));
    });

    test('pictures resolve inside the inbox and the lab', () {
      final lab = makeLab();
      final source = LocalHarvestSource(labDir: lab.path);
      final inbox = source.inboxImage('plate_specialist/images/a.jpg');
      expect(inbox, isA<FileImage>());
      expect((inbox as FileImage).file.path.replaceAll('\\', '/'), endsWith('training_lab/harvest_inbox/plate_specialist/images/a.jpg'));
      final lab2 = source.labImage('datasets/reid/images/t/c/1.jpg', width: 200);
      expect(lab2, isA<ResizeImage>());
    });
  });
}
