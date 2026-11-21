import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../domain/models/frame_job.dart';
import '../domain/models/road_detect.dart';
import '../domain/models/road_preset.dart';
import '../domain/models/setup_preset.dart';

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

  // ── Saved roads: the road markings of the setup under a name, to use again, duplicate and edit later ──

  Future<List<RoadPreset>> roadPresets({String? hash}) async {
    final body = await _json(await _client.get(_uri('/settings/road-presets', hash == null ? null : {'hash': hash})));
    return [for (final p in (body['presets'] as List? ?? const [])) RoadPreset.fromJson(Map<String, dynamic>.from(p as Map))];
  }

  /// The markings of a saved road (1920x1080 reference space).
  Future<List<RoadArea>> roadPresetMarkings(String id) async {
    final body = await _json(await _client.get(_uri('/settings/road-presets/$id')));
    return [for (final m in (body['markings'] as List? ?? const [])) if (m is Map) RoadArea.fromJson(Map<String, dynamic>.from(m))];
  }

  Future<RoadPreset> saveRoadPreset(String name, List<RoadArea> markings, {String? videoHash, String? videoName}) async =>
      RoadPreset.fromJson(await _json(await _client.post(
        _uri('/settings/road-presets'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'markings': [for (final m in markings) m.toJson()], 'video_hash': ?videoHash, 'video_name': ?videoName}),
      )));

  /// The fingerprint of the video file in use: {hash (null for a camera), name, size}. A saved setup or road is tied to it.
  Future<Map<String, dynamic>> videoHash() async => _json(await _client.get(_uri('/settings/video/hash')));

  /// The saved violation setups; with [hash] the ones saved for that video come first (match: true).
  Future<List<SetupPreset>> setupPresets(String? hash) async {
    final body = await _json(await _client.get(_uri('/settings/setup-presets', hash == null ? null : {'hash': hash})));
    return [for (final p in (body['presets'] as List? ?? const [])) SetupPreset.fromJson(Map<String, dynamic>.from(p as Map))];
  }

  /// The violations and settings of a saved setup (the live setup's shape).
  Future<Map<String, dynamic>> setupPresetConfig(String id) async {
    final body = await _json(await _client.get(_uri('/settings/setup-presets/$id')));
    return Map<String, dynamic>.from(body['config'] as Map? ?? const {});
  }

  Future<SetupPreset> saveSetupPreset(String name, Map<String, dynamic> config, {String? videoHash, String? videoName}) async =>
      SetupPreset.fromJson(await _json(await _client.post(
        _uri('/settings/setup-presets'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'config': config, 'video_hash': ?videoHash, 'video_name': ?videoName}),
      )));

  /// Replaces the setup kept under [id] with [config] (the name and the video stay).
  Future<SetupPreset> updateSetupPreset(String id, Map<String, dynamic> config) async => SetupPreset.fromJson(await _json(await _client.put(
    _uri('/settings/setup-presets/$id'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'config': config}),
  )));

  Future<void> deleteSetupPreset(String id) async => _json(await _client.delete(_uri('/settings/setup-presets/$id')));

  /// Changes what is sent: the [name] and/or the [markings].
  Future<RoadPreset> updateRoadPreset(String id, {String? name, List<RoadArea>? markings}) async => RoadPreset.fromJson(await _json(await _client.put(
    _uri('/settings/road-presets/$id'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'name': ?name, if (markings != null) 'markings': [for (final m in markings) m.toJson()]}),
  )));

  Future<RoadPreset> duplicateRoadPreset(String id) async =>
      RoadPreset.fromJson(await _json(await _client.post(_uri('/settings/road-presets/$id/duplicate'))));

  Future<void> deleteRoadPreset(String id) async => _json(await _client.delete(_uri('/settings/road-presets/$id')));

  /// Deletes every ticket the Live Monitor made before (database rows, report, evidence photos). Forensic analyses are not touched.
  /// {ok, tickets, rows, files}.
  Future<Map<String, dynamic>> clearLiveTickets() async => _json(await _client.delete(_uri('/settings/live/tickets')));

  /// Whether the next live runs are saved (every picture and its boxes, to replay later like a forensic run) and where: {save, dir, default_dir}.
  Future<Map<String, dynamic>> liveRecord() async => _json(await _client.get(_uri('/settings/live/record')));

  /// Choose to save the next live runs in [dir] (made when it does not exist), or not.
  Future<Map<String, dynamic>> setLiveRecord(bool save, String dir) async => _json(await _client.post(
    _uri('/settings/live/record'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'save': save, 'dir': dir}),
  ));

  /// The saved runs that can be replayed in the Live Monitor: {runs: [{id, started, pictures, tickets, source}], roots: [folder], active}.
  Future<Map<String, dynamic>> replayRuns() async => _json(await _client.get(_uri('/settings/replay/runs')));

  /// Make the saved run [run] (its folder name) the Live Monitor's source; the feed then plays it, with no models.
  Future<Map<String, dynamic>> openReplay(String run) async => _json(await _client.post(
    _uri('/settings/replay/open'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'run': run}),
  ));

  /// The live switch: {ready, setup: [rules], active: [rules on], cost_ms: {rule: ms per picture}, needs: {rule: what it needs}}.
  Future<Map<String, dynamic>> liveRules() async => _json(await _client.get(_uri('/settings/live/rules')));

  /// Switch the rules of the running monitoring: only [active] are judged from the next picture on. Returns the new state (as liveRules).
  Future<Map<String, dynamic>> setLiveRules(List<String> active) async => _json(await _client.post(
    _uri('/settings/live/rules'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'active': active}),
  ));

  /// What "Re-detect a part" needs of a saved run: {duration, rules, source, can, why}.
  Future<Map<String, dynamic>> replayInfo(String run) async => _json(await _client.get(_uri('/settings/replay/$run/info')));

  /// Run the detection again on [startS]..[endS] (seconds on the run's timeline) with [rules]: a Forensic analysis. {task_id, ...}
  Future<Map<String, dynamic>> startRedetect(String run, double startS, double endS, List<String> rules) async => _json(await _client.post(
    _uri('/settings/replay/redetect'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'run': run, 'start_s': startS, 'end_s': endS, 'rules': rules}),
  ));

  /// Progress of a Forensic analysis: {status, progress, ticket_count, message, error, ...}.
  Future<Map<String, dynamic>> forensicStatus(String taskId) async => _json(await _client.get(_uri('/api/forensic/status/$taskId')));

  /// Stop a Forensic analysis ([cancel]: throw it away; else keep what was found).
  Future<void> stopForensic(String taskId, {bool cancel = false}) async =>
      _json(await _client.post(_uri('/api/forensic/stop/$taskId', {'mode': cancel ? 'cancel' : 'finish'})));

  /// The box stabilizer (keeps a lost box on the screen for a moment): switch it, or set the seconds a box is held. Returns {on, hold_s, ghost_boxes, ...}.
  /// [keepConf]: the lowest score a vehicle that is tracked already keeps its box at (0 = off).
  Future<Map<String, dynamic>> setStabilizer({bool? on, double? holdS, double? keepConf}) async => _json(await _client.post(
    _uri('/settings/live/stabilizer'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'on': ?on, 'hold_s': ?holdS, 'keep_conf': ?keepConf}),
  ));

  /// "Save and pause": the setup, the source and the video position ([posS]) of the running monitoring are written into its run folder.
  Future<Map<String, dynamic>> saveSession(double posS) async => _json(await _client.post(
    _uri('/settings/live/session/save'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'pos_s': posS}),
  ));

  /// Go on with a saved monitoring: its setup, source and tickets come back. {pos_s, source_name, tickets}
  Future<Map<String, dynamic>> continueSession(String run) async => _json(await _client.post(
    _uri('/settings/live/session/continue'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'run': run}),
  ));

  /// A saved run without tickets of its own takes the tickets that are in the Live Monitor now.
  Future<Map<String, dynamic>> adoptReplayTickets(String run) async => _json(await _client.post(
    _uri('/settings/replay/adopt'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'run': run}),
  ));

  /// The Demo replay switch and the demos made so far: {on, demos: [{id, title, videos, pictures, tickets, duration_s}]}.
  Future<Map<String, dynamic>> demoState() async => _json(await _client.get(_uri('/settings/demo')));

  /// Demo replay on or off: a video file that has a demo plays its recorded run in the Live Monitor.
  Future<Map<String, dynamic>> setDemo(bool on) async => _json(await _client.post(
    _uri('/settings/demo'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'on': on}),
  ));

  /// Make a demo from the last saved live run and the live tickets as they are now. [video] empty = the run's own video file.
  Future<Map<String, dynamic>> createDemo(String title, String video) async => _json(await _client.post(
    _uri('/settings/demo/create'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'title': title, 'video': video}),
  ));

  Future<void> deleteDemo(String id) async => _json(await _client.delete(_uri('/settings/demo/$id')));

  /// The vehicles of a demo (for the demo editor): {tracks: [{track_id, kind, plate, violation, frames, first_s, last_s, tickets}], kinds, violations}.
  Future<Map<String, dynamic>> demoTracks(String id) async => _json(await _client.get(_uri('/settings/demo/$id/tracks')));

  /// The picture of one vehicle of a demo (a JPEG url).
  String demoTrackPictureUrl(String id, int trackId) => '$baseUrl/settings/demo/$id/track-picture/$trackId';

  /// Correct one vehicle of a demo in every picture and ticket. Only what is given changes: [kind], [plate], [violation] ('' = none), [delete].
  Future<Map<String, dynamic>> editDemoTrack(String id, int trackId, {String? kind, String? plate, String? violation, bool delete = false}) async =>
      _json(await _client.post(
        _uri('/settings/demo/$id/edit'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'track_id': trackId,
          'kind': ?kind,
          'plate': ?plate,
          'violation': ?violation,
          if (delete) 'delete': true,
        }),
      ));

  /// Empties the setup (violations, zones, road markings, setup picture): the Live Monitor starts empty each time it is opened.
  Future<void> resetLiveSetup() async => _json(await _client.post(_uri('/settings/live/reset')));

  /// Tells the backend the Live Monitor is about to start (Start or Set up violations was pressed): it loads and warms its models in the
  /// background while the setup is made, so Apply finds them ready. Fire and forget: it only saves time, so a failure is not an error.
  Future<void> prepareFeed() async {
    try {
      await _client.post(_uri('/settings/live/prepare')).timeout(const Duration(seconds: 4));
    } catch (_) {
      // the models then load when the feed starts, as before
    }
  }

  /// Everything the Performance popup shows (step times, a timeline of the last seconds, CPU / RAM / GPU load, the device of each model).
  Future<Map<String, dynamic>> livePerf({double window = 2.5}) async =>
      _json(await _client.get(_uri('/settings/live/perf', {'window': '$window'})).timeout(const Duration(seconds: 4)));

  /// The violations whose overlay objects (signs, painted crosswalks and lines) are hidden on the live picture.
  Future<List<String>> hiddenOverlays() async {
    final body = await _json(await _client.get(_uri('/settings/live/overlays')));
    return [for (final k in (body['hidden'] as List? ?? const [])) '$k'];
  }

  /// Hides the overlay objects of these violations on the live picture (the rules still judge). Takes effect on the next picture.
  Future<void> setHiddenOverlays(Iterable<String> keys) async => _json(await _client.put(
    _uri('/settings/live/overlays'),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({'hidden': keys.toList()}),
  ));

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
