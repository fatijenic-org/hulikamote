import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/features/forensic/data/forensic_api.dart';
import 'package:hulikamote_dashboard/features/forensic/data/object_previews.dart';

import 'support/test_support.dart';

/// The pictures of the overlay objects come from the backend (the same drawing as the evidence photos); the editor keeps them.
void main() {
  test('the key rounds what a slider cannot tell apart', () {
    expect(ObjectPreviews.keyOf('hydrant', 1.0, 10.4, -3.6, 'none', true), ObjectPreviews.keyOf('hydrant', 1.001, 10.0, -4.0, 'none', true));
    expect(ObjectPreviews.keyOf('hydrant', 1.0, 0, 0, 'none', true), isNot(ObjectPreviews.keyOf('hydrant', 1.0, 0, 0, 'none', false)));
    expect(ObjectPreviews.keyOf('sign', 1.0, 0, 0, 'post', true), isNot(ObjectPreviews.keyOf('sign', 1.0, 0, 0, 'tripod', true)));
  });

  test('without an API nothing is fetched and nothing is kept', () {
    final previews = ObjectPreviews(null);
    expect(previews.peek('hydrant'), isNull);
    expect(previews.peek('hydrant'), isNull);
    previews.dispose();
  });

  testWidgets('a picture is asked for once, kept, and the listeners hear when it arrives', (tester) async {
    final asked = <Uri>[];
    final api = ForensicApi(
      client: MockClient((req) async {
        asked.add(req.url);
        return http.Response.bytes(kTinyPng, 200, headers: {'x-offset-x': '-40', 'x-offset-y': '-110'});
      }),
    );
    final previews = ObjectPreviews(api);
    var heard = 0;
    previews.addListener(() => heard++);
    expect(previews.peek('hydrant', scale: 1.5, angle: 12, tilt: -20, stand: 'none', realistic: false), isNull); // on its way
    expect(previews.peek('hydrant', scale: 1.5, angle: 12, tilt: -20, stand: 'none', realistic: false), isNull); // not asked twice
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    expect(asked, hasLength(1));
    expect(asked.single.path, '/api/forensic/overlay-object');
    expect(asked.single.queryParameters, {
      'kind': 'hydrant', 'scale': '1.5', 'angle': '12.0', 'tilt': '-20.0', 'stand': 'none', 'realistic': 'false', 'frame_width': '1920',
    });
    final got = previews.peek('hydrant', scale: 1.5, angle: 12, tilt: -20, stand: 'none', realistic: false);
    expect(got, isNotNull);
    expect((got!.dx, got.dy), (-40.0, -110.0));
    expect(got.image.width, greaterThan(0));
    expect(heard, 1);
    expect(asked, hasLength(1));
    previews.dispose();
  });

  testWidgets('a backend that cannot draw the object, or does not answer, leaves a dot and no crash', (tester) async {
    for (final reply in <Future<http.Response> Function(http.Request)>[
      (r) async => http.Response('{"detail":"Not Found"}', 404),
      (r) async => throw Exception('no answer'),
      (r) async => http.Response.bytes([1, 2, 3], 200),
    ]) {
      final previews = ObjectPreviews(ForensicApi(client: MockClient(reply)));
      expect(previews.peek('sign'), isNull);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      expect(previews.peek('sign'), isNull);
      previews.dispose();
    }
  });
}
