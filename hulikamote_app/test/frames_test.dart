import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_app/core/config/app_config.dart';
import 'package:hulikamote_app/core/models/notice.dart';
import 'package:hulikamote_app/core/widgets/frame_gallery.dart';
import 'package:hulikamote_app/features/home/models/violation.dart';
import 'package:hulikamote_app/features/home/screens/violation_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Violation ticket(Object? evidence) => Violation.fromJson({
      'id': 'ab12cd34-0000', 'cls': 'no_helmet', 'confidence': 0.9, 'timestamp': '2026-10-29T08:00:00+00:00', 'image_path': '', 'evidence_paths': evidence,
    });

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'server_address': '192.168.68.109:8000'});
    await AppConfig.load();
  });

  group('photos in the data', () {
    test('a notice lists the photos that came with it', () {
      final n = Notice.fromJson({'id': 'n1', 'subject': 's', 'body': 'b', 'created_at': 't', 'frames': ['a.jpg', 'b.jpg']});
      expect(n.frames, ['a.jpg', 'b.jpg']);
      expect(Notice.fromJson({'id': 'n2'}).frames, isEmpty);                       // an old notice without photos
    });

    test('a ticket lists all its photos by bare file name, whatever the laptop stored', () {
      expect(ticket('["a.jpg", "snapshots/evidence/b.jpg", "C:\\\\x\\\\c.jpg"]').evidencePaths, ['a.jpg', 'b.jpg', 'c.jpg']);
      expect(ticket(['x.jpg']).evidencePaths, ['x.jpg']);
    });

    test('nothing usable gives no photos instead of an error', () {
      for (final bad in [null, '', 'not json', '{}', 5]) {
        expect(ticket(bad).evidencePaths, isEmpty, reason: '$bad');
      }
    });

    test('a photo is fetched from the evidence folder of the laptop', () {
      expect(FrameGallery.url('a b.jpg'), 'http://192.168.68.109:8000/snapshots/evidence/a%20b.jpg');
    });
  });

  group('close-ups kept as evidence', () {
    test('a close-up is recognised by its file name, here or online', () {
      expect(FrameGallery.caption('detail_helmet_1793749731411.jpg'), 'Helmet check');
      expect(FrameGallery.caption('u1/t1/detail_seatbelt_5.jpg'), 'Seatbelt check');
      expect(FrameGallery.caption('detail_phone_5.jpg'), 'Phone check');
      expect(FrameGallery.caption('detail_mirror_5.jpg'), 'Side-mirror check');
      expect(FrameGallery.caption('detail_something_5.jpg'), 'Close-up');
      expect(FrameGallery.caption('1793749731411.jpg'), isNull);                    // an ordinary photo has no caption
      expect(FrameGallery.caption('u1/t1/a.jpg'), isNull);
    });

    test('a ticket keeps its close-ups among its photos', () {
      expect(ticket(['a.jpg', 'detail_helmet_1.jpg', 'b.jpg']).evidencePaths, ['a.jpg', 'detail_helmet_1.jpg', 'b.jpg']);
    });

    testWidgets('the gallery labels a close-up and the full-screen view says what it is', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: FrameGallery(names: ['a.jpg', 'detail_helmet_1.jpg'])))));
      expect(find.text('Photos (2)'), findsOneWidget);
      expect(find.text('Helmet check'), findsOneWidget);                              // only the close-up has a label

      await tester.tap(find.byType(InkWell).at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Photo 2 of 2 · Helmet check'), findsOneWidget);
    });
  });

  group('looking at the photos', () {
    testWidgets('the gallery shows how many there are and opens them full screen', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: FrameGallery(names: ['a.jpg', 'b.jpg', 'c.jpg'])))));
      expect(find.text('Photos (3)'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(3));

      await tester.tap(find.byType(InkWell).at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Photo 2 of 3'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Photo 3 of 3'), findsOneWidget);
    });

    testWidgets('without photos the gallery takes no room', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: FrameGallery(names: []))));
      expect(find.text('Photos (0)'), findsNothing);
    });

    testWidgets('the ticket page shows all the ticket\'s photos', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ViolationDetailScreen(violation: ticket(['a.jpg', 'b.jpg']))));
      expect(find.text('Photos (2)'), findsOneWidget);
    });
  });
}
