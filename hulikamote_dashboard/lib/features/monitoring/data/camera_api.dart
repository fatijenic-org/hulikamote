import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../domain/models/frame_job.dart';
import '../domain/models/road_detect.dart';

/// A saved camera address. The backend never sends passwords back: they show as `***`.
class CameraProfile {
  const CameraProfile({required this.name, required this.url, this.kind = ''});

  final String name;
  final String url;
  final String kind; // rtsp | http | stream | webcam | file | invalid

  factory CameraProfile.fromJson(Map<String, dynamic> json) =>
      CameraProfile(name: json['name'] as String, url: json['url'] as String, kind: (json['kind'] ?? '') as String);
}

/// What the Test button found.
class CameraTestResult {
  const CameraTestResult({required this.ok, this.message = '', this.width = 0, this.height = 0, this.fps = 0, this.firstFrameMs = 0});

  final bool ok;
  final String message;
  final int width;
  final int height;
  final double fps;
  final int firstFrameMs;

  factory CameraTestResult.fromJson(Map<String, dynamic> json) => CameraTestResult(
        ok: json['ok'] == true,
        message: (json['error'] ?? '') as String,
        width: (json['width'] ?? 0) as int,
        height: (json['height'] ?? 0) as int,
        fps: ((json['fps'] ?? 0) as num).toDouble(),
        firstFrameMs: (json['first_frame_ms'] ?? 0) as int,
      );

  /// "1280x720 at 15 fps, first picture after 3.5 s" or the reason it failed.
  String get summary => ok
      ? '${width}x$height at ${fps.toStringAsFixed(0)} fps, first picture after ${(firstFrameMs / 1000).toStringAsFixed(1)} s'
      : message;
}

/// The backend's camera-input endpoints (see hulikamote_backend/routers/settings.py).
class CameraApi {
  CameraApi({http.Client? client, this.baseUrl = ApiConstants.baseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _json(http.Response res) async {
    final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      throw Exception(detail ?? 'Request failed (${res.statusCode})');
    }
    return body as Map<String, dynamic>;
  }

  Future<List<CameraProfile>> profiles() async {
    final body = await _json(await _client.get(_uri('/settings/camera-profiles')));
    return [for (final p in (body['profiles'] as List)) CameraProfile.fromJson(p as Map<String, dynamic>)];
  }

  Future<void> saveProfiles(List<CameraProfile> profiles) async {
    final res = await _client.put(
      _uri('/settings/camera-profiles'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'profiles': [for (final p in profiles) {'name': p.name, 'url': p.url}],
      }),
    );
    await _json(res);
  }

  /// Test a typed address, or a saved profile by name (so a hidden password is still used).
  Future<CameraTestResult> test({String? address, String? profile}) async {
    final res = await _client.post(
      _uri('/settings/video/test', address != null ? {'path': address} : {'name': profile!}),
    );
    return CameraTestResult.fromJson(await _json(res));
  }

  /// Make an address, or a saved profile by name, the live monitor's source. Returns the masked label.
  Future<String> use({String? address, String? profile}) async {
    final res = address != null
        ? await _client.post(_uri('/settings/video/source', {'path': address}))
        : await _client.post(_uri('/settings/camera-profiles/use', {'name': profile!}));
    return ((await _json(res))['label'] ?? '') as String;
  }

  /// Learn the road paint of the connected camera again from the live stream.
  Future<void> relearnRoad() async => _json(await _client.post(_uri('/settings/video/road/relearn')));

  /// Remove what was learned for the connected camera (also from the saved file).
  Future<void> forgetRoad() async => _json(await _client.post(_uri('/settings/video/road/forget')));

  // ── "Detect road": freeze a frame, read the road, show every step, then apply or discard ──

  /// Press of the Detect road button. Throws with the backend's reason (no picture yet, already running).
  Future<RoadDetectStatus> startRoadDetect() async {
    final body = await _json(await _client.post(_uri('/settings/video/road/detect')));
    if (body['ok'] != true) throw Exception(body['reason'] ?? 'Could not start reading the road');
    return RoadDetectStatus.fromJson(Map<String, dynamic>.from(body['detect'] as Map));
  }

  // With [scan] the same calls read the setup's road scan (see [startRoadScan]) instead of "Detect road".
  String _detectPath(bool scan) => scan ? '/settings/video/scan' : '/settings/video/road/detect';

  Future<RoadDetectStatus> roadDetectStatus({bool scan = false}) async =>
      RoadDetectStatus.fromJson(await _json(await _client.get(_uri(_detectPath(scan)))));

  /// The frozen picture (JPEG), or null when there is no detection.
  Future<Uint8List?> roadDetectFrame({bool scan = false}) => _bytes('${_detectPath(scan)}/frame');

  /// A finished step's picture (PNG with see-through parts), or null when that step has none.
  Future<Uint8List?> roadDetectStep(String id, {bool scan = false}) => _bytes('${_detectPath(scan)}/step/$id');

  /// The setup's "Find the road automatically": the same walkthrough as Detect road, on a few seconds of the source that start at the
  /// setup picture. Poll it with `roadDetectStatus(scan: true)`. Throws with the backend's reason.
  Future<RoadDetectStatus> startRoadScan() async {
    final body = await _json(await _client.post(_uri('/settings/video/scan')));
    if (body['ok'] != true) throw Exception(body['reason'] ?? 'Could not start reading the road');
    return RoadDetectStatus.fromJson(Map<String, dynamic>.from(body['detect'] as Map));
  }

  Future<Uint8List?> _bytes(String path) async {
    final res = await _client.get(_uri(path));
    return res.statusCode == 200 ? res.bodyBytes : null;
  }

  /// Use what was found. {ok, zones, switched_on} or {ok: false, reason}. With [counterflow] the road sides that have a direction also
  /// become Counterflow zones (traffic against the arrow is flagged).
  Future<Map<String, dynamic>> applyRoadDetect({bool counterflow = false}) async =>
      _json(await _client.post(_uri('/settings/video/road/detect/apply', counterflow ? {'counterflow': 'true'} : null)));

  /// The operator's corrections to the draft (areas in the frozen picture's pixels). Apply then saves these.
  Future<Map<String, dynamic>> correctRoadDetect(List<RoadArea> areas) async => _json(await _client.post(
    _uri('/settings/video/road/detect/zones'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'zones': [for (final a in areas) a.toJson()]}),
  ));

  Future<void> discardRoadDetect({bool scan = false}) async => _json(await _client.post(_uri('${_detectPath(scan)}/discard')));

  // ── "Set up violations": freeze one picture of the running camera, then set the violations up on it ──

  /// Freezes the newest picture. {ok: true, version, width, height, fps} or {ok: false, reason} (no picture yet).
  Future<Map<String, dynamic>> captureReference() async => _json(await _client.post(_uri('/settings/video/reference')));

  /// Where the frozen picture is served; [version] keeps the image cache from showing an older one.
  String referenceFrameUrl(int version) => '$baseUrl/settings/video/reference/frame?v=$version';

  /// The frozen setup picture itself (JPEG), or null when there is none (the road markings are drawn on it).
  Future<Uint8List?> referenceFrameBytes() => _bytes('/settings/video/reference/frame');

  /// The violations and settings the Live Monitor uses now, in the wizard's own shape ({} when none were set up).
  Future<Map<String, dynamic>> liveSetup() async => _json(await _client.get(_uri('/settings/live/setup')));

  // ── The "pick a frame" step: a few pictures of the source, then one of them becomes the setup picture ──

  /// Starts collecting pictures of the current source (a file: spread over the video; a camera: one a second for a few seconds).
  Future<FrameJob> startFrames({int count = 8}) async =>
      FrameJob.fromJson(await _json(await _client.post(_uri('/settings/video/frames/start', {'count': '$count'}))));

  /// The pictures collected so far (they arrive one by one while [FrameJob.working]).
  Future<FrameJob> frames() async => FrameJob.fromJson(await _json(await _client.get(_uri('/settings/video/frames'))));

  /// Where a collected picture is served; [job] keeps the image cache from showing a picture of an older grab.
  String frameUrl(int job, int id) => '$baseUrl/settings/video/frames/$id?job=$job';

  /// Makes a collected picture the one the violations are set up on. {ok: true, version, width, height, fps} or {ok: false, reason}.
  Future<Map<String, dynamic>> useFrame(int id) async => _json(await _client.post(_uri('/settings/video/frames/$id/use')));

  // ── Traffic flow: Counterflow demo ──

  /// Demo: on = the opposite of the legal direction counts as legal, so ordinary traffic is flagged. {ok, reversed} or {ok: false, reason}.
  Future<Map<String, dynamic>> reverseFlow(bool on) async =>
      _json(await _client.post(_uri('/settings/live/flow/reverse', {'on': '$on'})));

  /// Forget the learned traffic flow and learn it again.
  Future<Map<String, dynamic>> relearnFlow() async => _json(await _client.post(_uri('/settings/live/flow/relearn')));

  /// "Connect phone": finds the HULI-KAMOTE Camera app by itself (USB tethering, the phone's hotspot, the same Wi-Fi or a USB cable),
  /// saves it as the camera "Phone" and makes it the live source. {ok, via, url, message, steps: [{text, ok}]}.
  /// ok == false is a normal answer: [message] says what to do. Can take half a minute (the whole network is looked at).
  Future<Map<String, dynamic>> connectPhone() async =>
      _json(await _client.post(_uri('/settings/phone/connect')).timeout(const Duration(seconds: 90)));

  /// state: live | connecting | offline | file | idle ...
  Future<Map<String, dynamic>> status() async => _json(await _client.get(_uri('/settings/video/status')));
}
